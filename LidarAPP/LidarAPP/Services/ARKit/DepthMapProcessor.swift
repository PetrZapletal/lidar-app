import ARKit
import simd
import Accelerate
import CoreImage

/// Processes and enhances LiDAR depth maps
final class DepthMapProcessor: Sendable {

    // MARK: - Configuration

    struct Configuration: Sendable {
        var minValidDepth: Float = 0.1
        var maxValidDepth: Float = 5.0
        var edgeThreshold: Float = 0.1
        var smoothingRadius: Int = 3
        var holeFillMaxSize: Int = 10
        var confidenceThreshold: Float = 0.5
    }

    // MARK: - Depth Statistics

    struct DepthStatistics: Sendable {
        let minDepth: Float
        let maxDepth: Float
        let meanDepth: Float
        let medianDepth: Float
        let standardDeviation: Float
        let validPixelCount: Int
        let totalPixelCount: Int
        let coverage: Float
        let histogram: [Int]

        var depthRange: Float { maxDepth - minDepth }
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let ciContext: CIContext

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    // MARK: - Depth Analysis

    /// Compute comprehensive depth statistics
    func computeStatistics(from depthMap: CVPixelBuffer) -> DepthStatistics {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let totalCount = width * height

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return emptyStatistics(totalCount: totalCount)
        }

        let depthData = baseAddress.assumingMemoryBound(to: Float32.self)

        var validDepths: [Float] = []
        validDepths.reserveCapacity(totalCount / 2)

        var histogram = [Int](repeating: 0, count: 100)

        for i in 0..<totalCount {
            let depth = depthData[i]
            if depth > configuration.minValidDepth && depth < configuration.maxValidDepth {
                validDepths.append(depth)

                let normalizedDepth = (depth - configuration.minValidDepth) /
                                      (configuration.maxValidDepth - configuration.minValidDepth)
                let bin = min(99, max(0, Int(normalizedDepth * 100)))
                histogram[bin] += 1
            }
        }

        guard !validDepths.isEmpty else {
            return emptyStatistics(totalCount: totalCount)
        }

        validDepths.sort()

        let minDepth = validDepths.first!
        let maxDepth = validDepths.last!
        let medianDepth = validDepths[validDepths.count / 2]

        var mean: Float = 0
        vDSP_meanv(validDepths, 1, &mean, vDSP_Length(validDepths.count))

        var squaredDiff = [Float](repeating: 0, count: validDepths.count)
        let meanVec = [Float](repeating: mean, count: validDepths.count)

        vDSP_vsub(meanVec, 1, validDepths, 1, &squaredDiff, 1, vDSP_Length(validDepths.count))
        vDSP_vsq(squaredDiff, 1, &squaredDiff, 1, vDSP_Length(validDepths.count))

        var variance: Float = 0
        vDSP_meanv(squaredDiff, 1, &variance, vDSP_Length(validDepths.count))
        let stdDev = sqrt(variance)

        return DepthStatistics(
            minDepth: minDepth,
            maxDepth: maxDepth,
            meanDepth: mean,
            medianDepth: medianDepth,
            standardDeviation: stdDev,
            validPixelCount: validDepths.count,
            totalPixelCount: totalCount,
            coverage: Float(validDepths.count) / Float(totalCount),
            histogram: histogram
        )
    }

    private func emptyStatistics(totalCount: Int) -> DepthStatistics {
        DepthStatistics(
            minDepth: 0, maxDepth: 0, meanDepth: 0, medianDepth: 0,
            standardDeviation: 0, validPixelCount: 0, totalPixelCount: totalCount,
            coverage: 0, histogram: [Int](repeating: 0, count: 100)
        )
    }

    // MARK: - Depth Enhancement

    /// Apply bilateral filter to smooth depth while preserving edges
    func bilateralFilter(depthMap: CVPixelBuffer) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard let inputBase = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let inputData = inputBase.assumingMemoryBound(to: Float32.self)

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &outputBuffer
        )

        guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }

        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        guard let outputBase = CVPixelBufferGetBaseAddress(output) else { return nil }
        let outputData = outputBase.assumingMemoryBound(to: Float32.self)

        let radius = configuration.smoothingRadius
        let sigmaSpace: Float = Float(radius) / 2.0
        let sigmaRange: Float = configuration.edgeThreshold

        for y in 0..<height {
            for x in 0..<width {
                let centerIndex = y * width + x
                let centerDepth = inputData[centerIndex]

                if centerDepth <= configuration.minValidDepth ||
                   centerDepth >= configuration.maxValidDepth {
                    outputData[centerIndex] = centerDepth
                    continue
                }

                var weightSum: Float = 0
                var valueSum: Float = 0

                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx
                        let ny = y + dy

                        guard nx >= 0 && nx < width && ny >= 0 && ny < height else { continue }

                        let neighborIndex = ny * width + nx
                        let neighborDepth = inputData[neighborIndex]

                        guard neighborDepth > configuration.minValidDepth &&
                              neighborDepth < configuration.maxValidDepth else { continue }

                        let spatialDist = sqrt(Float(dx * dx + dy * dy))
                        let spatialWeight = exp(-spatialDist * spatialDist / (2 * sigmaSpace * sigmaSpace))

                        let rangeDist = abs(neighborDepth - centerDepth)
                        let rangeWeight = exp(-rangeDist * rangeDist / (2 * sigmaRange * sigmaRange))

                        let weight = spatialWeight * rangeWeight
                        weightSum += weight
                        valueSum += weight * neighborDepth
                    }
                }

                outputData[centerIndex] = weightSum > 0 ? valueSum / weightSum : centerDepth
            }
        }

        return output
    }

    /// Fill small holes in depth map using inpainting
    func fillHoles(in depthMap: CVPixelBuffer) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard let inputBase = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let inputData = inputBase.assumingMemoryBound(to: Float32.self)

        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &outputBuffer
        )

        guard let output = outputBuffer else { return nil }

        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        guard let outputBase = CVPixelBufferGetBaseAddress(output) else { return nil }
        let outputData = outputBase.assumingMemoryBound(to: Float32.self)

        memcpy(outputData, inputData, width * height * MemoryLayout<Float32>.stride)

        let maxSize = configuration.holeFillMaxSize

        for _ in 0..<maxSize {
            var changed = false

            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let index = y * width + x
                    let depth = outputData[index]

                    if depth <= configuration.minValidDepth ||
                       depth >= configuration.maxValidDepth {

                        var validNeighbors: [Float] = []

                        let neighbors = [
                            (x - 1, y), (x + 1, y),
                            (x, y - 1), (x, y + 1)
                        ]

                        for (nx, ny) in neighbors {
                            let neighborIndex = ny * width + nx
                            let neighborDepth = outputData[neighborIndex]

                            if neighborDepth > configuration.minValidDepth &&
                               neighborDepth < configuration.maxValidDepth {
                                validNeighbors.append(neighborDepth)
                            }
                        }

                        if validNeighbors.count >= 3 {
                            outputData[index] = validNeighbors.reduce(0, +) / Float(validNeighbors.count)
                            changed = true
                        }
                    }
                }
            }

            if !changed { break }
        }

        return output
    }

    // MARK: - Confidence Map Processing

    /// Analyze confidence map distribution
    func analyzeConfidence(from confidenceMap: CVPixelBuffer) -> (low: Float, medium: Float, high: Float) {
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)
        let totalCount = width * height

        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            return (0, 0, 0)
        }

        let confData = baseAddress.assumingMemoryBound(to: UInt8.self)

        var lowCount = 0
        var mediumCount = 0
        var highCount = 0

        for i in 0..<totalCount {
            switch confData[i] {
            case 0: lowCount += 1
            case 1: mediumCount += 1
            case 2: highCount += 1
            default: break
            }
        }

        let total = Float(totalCount)
        return (
            low: Float(lowCount) / total,
            medium: Float(mediumCount) / total,
            high: Float(highCount) / total
        )
    }

    /// Create mask for high-confidence regions
    func createHighConfidenceMask(
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer
    ) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap),
              let confBase = CVPixelBufferGetBaseAddress(confidenceMap) else { return nil }

        let depthData = depthBase.assumingMemoryBound(to: Float32.self)
        let confData = confBase.assumingMemoryBound(to: UInt8.self)

        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &outputBuffer
        )

        guard let output = outputBuffer else { return nil }

        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        guard let outputBase = CVPixelBufferGetBaseAddress(output) else { return nil }
        let outputData = outputBase.assumingMemoryBound(to: Float32.self)

        for i in 0..<(width * height) {
            let confidence = Float(confData[i]) / 2.0
            outputData[i] = confidence >= configuration.confidenceThreshold ? depthData[i] : 0
        }

        return output
    }
}
