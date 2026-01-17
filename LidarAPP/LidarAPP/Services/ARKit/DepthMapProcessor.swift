import ARKit
import simd
import Accelerate
import CoreImage

/// Processes and enhances LiDAR depth maps
final class DepthMapProcessor: Sendable {

    // MARK: - Configuration

    struct Configuration: Sendable {
        var minValidDepth: Float = 0.1       // 10cm minimum
        var maxValidDepth: Float = 5.0       // 5m maximum
        var edgeThreshold: Float = 0.1       // For edge detection
        var smoothingRadius: Int = 3         // Bilateral filter radius
        var holeFillMaxSize: Int = 10        // Max hole size to fill (pixels)
        var confidenceThreshold: Float = 0.5 // Minimum confidence
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
        let histogram: [Int]  // 100 bins

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

        // Collect valid depths
        var validDepths: [Float] = []
        validDepths.reserveCapacity(totalCount / 2)

        var histogram = [Int](repeating: 0, count: 100)

        for i in 0..<totalCount {
            let depth = depthData[i]
            if depth > configuration.minValidDepth && depth < configuration.maxValidDepth {
                validDepths.append(depth)

                // Update histogram (map depth to 0-99 bin)
                let normalizedDepth = (depth - configuration.minValidDepth) /
                                      (configuration.maxValidDepth - configuration.minValidDepth)
                let bin = min(99, max(0, Int(normalizedDepth * 100)))
                histogram[bin] += 1
            }
        }

        guard !validDepths.isEmpty else {
            return emptyStatistics(totalCount: totalCount)
        }

        // Sort for median
        validDepths.sort()

        let minDepth = validDepths.first!
        let maxDepth = validDepths.last!
        let medianDepth = validDepths[validDepths.count / 2]

        // Calculate mean using Accelerate
        var mean: Float = 0
        vDSP_meanv(validDepths, 1, &mean, vDSP_Length(validDepths.count))

        // Calculate standard deviation
        var stdDev: Float = 0
        var squaredDiff = [Float](repeating: 0, count: validDepths.count)
        var meanVec = [Float](repeating: mean, count: validDepths.count)

        vDSP_vsub(meanVec, 1, validDepths, 1, &squaredDiff, 1, vDSP_Length(validDepths.count))
        vDSP_vsq(squaredDiff, 1, &squaredDiff, 1, vDSP_Length(validDepths.count))

        var variance: Float = 0
        vDSP_meanv(squaredDiff, 1, &variance, vDSP_Length(validDepths.count))
        stdDev = sqrt(variance)

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

        // Create output buffer
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

        // Apply bilateral filter
        for y in 0..<height {
            for x in 0..<width {
                let centerIndex = y * width + x
                let centerDepth = inputData[centerIndex]

                // Skip invalid depths
                if centerDepth <= configuration.minValidDepth ||
                   centerDepth >= configuration.maxValidDepth {
                    outputData[centerIndex] = centerDepth
                    continue
                }

                var weightSum: Float = 0
                var valueSum: Float = 0

                // Iterate over neighborhood
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx
                        let ny = y + dy

                        guard nx >= 0 && nx < width && ny >= 0 && ny < height else { continue }

                        let neighborIndex = ny * width + nx
                        let neighborDepth = inputData[neighborIndex]

                        // Skip invalid neighbors
                        guard neighborDepth > configuration.minValidDepth &&
                              neighborDepth < configuration.maxValidDepth else { continue }

                        // Spatial weight
                        let spatialDist = sqrt(Float(dx * dx + dy * dy))
                        let spatialWeight = exp(-spatialDist * spatialDist / (2 * sigmaSpace * sigmaSpace))

                        // Range weight
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

        // Create output buffer
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

        // Copy input to output first
        memcpy(outputData, inputData, width * height * MemoryLayout<Float32>.stride)

        let maxSize = configuration.holeFillMaxSize

        // Simple iterative hole filling
        for _ in 0..<maxSize {
            var changed = false

            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let index = y * width + x
                    let depth = outputData[index]

                    // Check if this is a hole
                    if depth <= configuration.minValidDepth ||
                       depth >= configuration.maxValidDepth {

                        // Collect valid neighbors
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

                        // Fill if we have enough neighbors
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

    // MARK: - Edge Detection

    struct DepthEdge: Sendable {
        let x: Int
        let y: Int
        let magnitude: Float
        let direction: Float  // Radians
    }

    /// Detect edges in depth map using Sobel operator
    func detectEdges(in depthMap: CVPixelBuffer) -> [DepthEdge] {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return [] }
        let depthData = baseAddress.assumingMemoryBound(to: Float32.self)

        var edges: [DepthEdge] = []

        // Sobel kernels
        let sobelX: [[Float]] = [
            [-1, 0, 1],
            [-2, 0, 2],
            [-1, 0, 1]
        ]

        let sobelY: [[Float]] = [
            [-1, -2, -1],
            [ 0,  0,  0],
            [ 1,  2,  1]
        ]

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                var gx: Float = 0
                var gy: Float = 0

                // Apply Sobel kernels
                for ky in -1...1 {
                    for kx in -1...1 {
                        let index = (y + ky) * width + (x + kx)
                        let depth = depthData[index]

                        // Skip invalid depths
                        guard depth > configuration.minValidDepth &&
                              depth < configuration.maxValidDepth else { continue }

                        gx += depth * sobelX[ky + 1][kx + 1]
                        gy += depth * sobelY[ky + 1][kx + 1]
                    }
                }

                let magnitude = sqrt(gx * gx + gy * gy)

                if magnitude > configuration.edgeThreshold {
                    let direction = atan2(gy, gx)
                    edges.append(DepthEdge(
                        x: x, y: y,
                        magnitude: magnitude,
                        direction: direction
                    ))
                }
            }
        }

        return edges
    }

    // MARK: - Depth Map Conversion

    /// Convert depth map to visualization-friendly image
    func createVisualization(
        from depthMap: CVPixelBuffer,
        colorMap: ColorMap = .turbo
    ) -> CVPixelBuffer? {
        let stats = computeStatistics(from: depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard let inputBase = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let depthData = inputBase.assumingMemoryBound(to: Float32.self)

        // Create BGRA output buffer
        var outputBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &outputBuffer
        )

        guard let output = outputBuffer else { return nil }

        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        guard let outputBase = CVPixelBufferGetBaseAddress(output) else { return nil }
        let rgbaData = outputBase.assumingMemoryBound(to: UInt8.self)

        let depthRange = stats.maxDepth - stats.minDepth

        for i in 0..<(width * height) {
            let depth = depthData[i]
            let pixelOffset = i * 4

            if depth <= configuration.minValidDepth || depth >= configuration.maxValidDepth {
                // Invalid depth - black
                rgbaData[pixelOffset] = 0     // B
                rgbaData[pixelOffset + 1] = 0 // G
                rgbaData[pixelOffset + 2] = 0 // R
                rgbaData[pixelOffset + 3] = 255 // A
            } else {
                // Normalize depth to 0-1
                let normalized = depthRange > 0 ?
                    (depth - stats.minDepth) / depthRange : 0.5

                let (r, g, b) = colorMap.getColor(for: normalized)
                rgbaData[pixelOffset] = UInt8(b * 255)     // B
                rgbaData[pixelOffset + 1] = UInt8(g * 255) // G
                rgbaData[pixelOffset + 2] = UInt8(r * 255) // R
                rgbaData[pixelOffset + 3] = 255            // A
            }
        }

        return output
    }

    // MARK: - Color Maps

    enum ColorMap {
        case grayscale
        case turbo
        case viridis
        case jet

        func getColor(for value: Float) -> (r: Float, g: Float, b: Float) {
            let v = max(0, min(1, value))

            switch self {
            case .grayscale:
                return (v, v, v)

            case .turbo:
                return turboColorMap(v)

            case .viridis:
                return viridisColorMap(v)

            case .jet:
                return jetColorMap(v)
            }
        }

        private func turboColorMap(_ t: Float) -> (Float, Float, Float) {
            // Simplified turbo colormap approximation
            let r = max(0, min(1, 0.84 - 0.84 * cos(3.14159 * (t * 0.8 + 0.2))))
            let g = max(0, min(1, sin(3.14159 * t)))
            let b = max(0, min(1, 0.84 * cos(3.14159 * (t * 0.8))))
            return (r, g, b)
        }

        private func viridisColorMap(_ t: Float) -> (Float, Float, Float) {
            // Simplified viridis approximation
            let r = max(0, min(1, 0.267 + t * 0.329))
            let g = max(0, min(1, 0.004 + t * 0.873))
            let b = max(0, min(1, 0.329 - t * 0.067 + t * t * 0.267))
            return (r, g, b)
        }

        private func jetColorMap(_ t: Float) -> (Float, Float, Float) {
            var r: Float = 0, g: Float = 0, b: Float = 0

            if t < 0.25 {
                r = 0
                g = 4 * t
                b = 1
            } else if t < 0.5 {
                r = 0
                g = 1
                b = 1 - 4 * (t - 0.25)
            } else if t < 0.75 {
                r = 4 * (t - 0.5)
                g = 1
                b = 0
            } else {
                r = 1
                g = 1 - 4 * (t - 0.75)
                b = 0
            }

            return (r, g, b)
        }
    }
}

// MARK: - Confidence Map Processing

extension DepthMapProcessor {

    /// Analyze confidence map
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

        // Create output depth buffer with only high-confidence values
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
            let confidence = Float(confData[i]) / 2.0  // 0, 0.5, 1.0

            if confidence >= configuration.confidenceThreshold {
                outputData[i] = depthData[i]
            } else {
                outputData[i] = 0  // Mark as invalid
            }
        }

        return output
    }
}
