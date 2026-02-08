import ARKit
import CoreML
import simd
import Accelerate

/// Fuses LiDAR depth with AI-enhanced depth for high-resolution output
@MainActor
final class DepthFusionProcessor {

    // MARK: - Configuration

    struct Configuration {
        /// Output resolution multiplier (relative to LiDAR)
        var resolutionMultiplier: Int = 4  // 256×192 → 1024×768

        /// Weight for LiDAR depth in high-confidence regions
        var lidarWeight: Float = 0.8

        /// Weight for AI depth in low-confidence regions
        var aiWeight: Float = 0.9

        /// Edge-aware blending radius
        var blendRadius: Int = 5

        /// Minimum confidence for LiDAR trust
        var lidarConfidenceThreshold: Float = 0.5

        /// Enable edge-preserving fusion
        var preserveEdges: Bool = true

        /// Maximum depth discontinuity for edge detection (meters)
        var edgeThreshold: Float = 0.1
    }

    // MARK: - Fusion Result

    struct FusionResult {
        /// High-resolution fused depth map
        let fusedDepth: CVPixelBuffer

        /// Confidence map for fused depth
        let confidenceMap: CVPixelBuffer

        /// Edge map (for mesh refinement)
        let edgeMap: CVPixelBuffer?

        /// Original LiDAR resolution
        let lidarResolution: CGSize

        /// Output resolution
        let outputResolution: CGSize

        /// Processing statistics
        let stats: FusionStats
    }

    struct FusionStats {
        let lidarCoverage: Float        // Percentage of valid LiDAR pixels
        let aiContribution: Float       // Percentage filled by AI
        let edgePixels: Int             // Number of detected edges
        let processingTimeMs: Double
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let depthAnythingModel: DepthAnythingModel

    /// Initialization state
    private(set) var isInitialized: Bool = false

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.depthAnythingModel = DepthAnythingModel()
    }

    /// Initialize the processor (load ML model)
    func initialize() async throws {
        try await depthAnythingModel.loadModel()
        isInitialized = depthAnythingModel.isLoaded
    }

    // MARK: - Depth Fusion

    /// Fuse LiDAR depth with AI-enhanced depth
    func fuseDepth(
        from frame: ARFrame
    ) async throws -> FusionResult {
        let startTime = CACurrentMediaTime()

        guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            throw DepthFusionError.noDepthData
        }

        let lidarDepth = sceneDepth.depthMap
        let lidarConfidence = sceneDepth.confidenceMap
        let rgbImage = frame.capturedImage

        return try await fuseDepth(
            lidarDepth: lidarDepth,
            lidarConfidence: lidarConfidence,
            rgbImage: rgbImage,
            startTime: startTime
        )
    }

    /// Fuse LiDAR and AI depth from raw buffers
    func fuseDepth(
        lidarDepth: CVPixelBuffer,
        lidarConfidence: CVPixelBuffer?,
        rgbImage: CVPixelBuffer,
        startTime: CFTimeInterval = CACurrentMediaTime()
    ) async throws -> FusionResult {
        // Get AI depth prediction
        let aiPrediction: DepthAnythingModel.DepthPrediction

        if depthAnythingModel.isLoaded {
            if let confidence = lidarConfidence {
                aiPrediction = try await depthAnythingModel.predictMetricDepth(
                    from: rgbImage,
                    lidarDepth: lidarDepth,
                    lidarConfidence: confidence
                )
            } else {
                aiPrediction = try await depthAnythingModel.predictDepth(from: rgbImage)
            }
        } else {
            // Fallback: just upscale LiDAR
            return try createFallbackResult(
                lidarDepth: lidarDepth,
                lidarConfidence: lidarConfidence,
                startTime: startTime
            )
        }

        // Get metric AI depth (or use relative if normalization failed)
        let aiDepth = aiPrediction.metricDepth ?? aiPrediction.relativeDepth

        // Perform fusion
        let (fusedDepth, confidenceMap, stats) = try performFusion(
            lidarDepth: lidarDepth,
            lidarConfidence: lidarConfidence,
            aiDepth: aiDepth
        )

        // Detect edges for mesh refinement
        let edgeMap = configuration.preserveEdges ?
            detectDepthEdges(in: fusedDepth) : nil

        let lidarWidth = CVPixelBufferGetWidth(lidarDepth)
        let lidarHeight = CVPixelBufferGetHeight(lidarDepth)
        let outputWidth = CVPixelBufferGetWidth(fusedDepth)
        let outputHeight = CVPixelBufferGetHeight(fusedDepth)

        let processingTime = (CACurrentMediaTime() - startTime) * 1000

        return FusionResult(
            fusedDepth: fusedDepth,
            confidenceMap: confidenceMap,
            edgeMap: edgeMap,
            lidarResolution: CGSize(width: lidarWidth, height: lidarHeight),
            outputResolution: CGSize(width: outputWidth, height: outputHeight),
            stats: FusionStats(
                lidarCoverage: stats.lidarCoverage,
                aiContribution: stats.aiContribution,
                edgePixels: edgeMap != nil ? countEdgePixels(edgeMap!) : 0,
                processingTimeMs: processingTime
            )
        )
    }

    // MARK: - Core Fusion Algorithm

    private func performFusion(
        lidarDepth: CVPixelBuffer,
        lidarConfidence: CVPixelBuffer?,
        aiDepth: CVPixelBuffer
    ) throws -> (depth: CVPixelBuffer, confidence: CVPixelBuffer, stats: (lidarCoverage: Float, aiContribution: Float)) {
        // Lock buffers
        CVPixelBufferLockBaseAddress(lidarDepth, .readOnly)
        CVPixelBufferLockBaseAddress(aiDepth, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(lidarDepth, .readOnly)
            CVPixelBufferUnlockBaseAddress(aiDepth, .readOnly)
        }

        if let conf = lidarConfidence {
            CVPixelBufferLockBaseAddress(conf, .readOnly)
        }
        defer {
            if let conf = lidarConfidence {
                CVPixelBufferUnlockBaseAddress(conf, .readOnly)
            }
        }

        let lidarWidth = CVPixelBufferGetWidth(lidarDepth)
        let lidarHeight = CVPixelBufferGetHeight(lidarDepth)
        let aiWidth = CVPixelBufferGetWidth(aiDepth)
        let aiHeight = CVPixelBufferGetHeight(aiDepth)

        // Output at AI resolution (higher)
        let outputWidth = aiWidth
        let outputHeight = aiHeight

        guard let lidarBase = CVPixelBufferGetBaseAddress(lidarDepth),
              let aiBase = CVPixelBufferGetBaseAddress(aiDepth) else {
            throw DepthFusionError.bufferAccessFailed
        }

        let lidarData = lidarBase.assumingMemoryBound(to: Float32.self)
        let aiData = aiBase.assumingMemoryBound(to: Float32.self)

        var confidenceData: UnsafeMutablePointer<UInt8>?
        if let conf = lidarConfidence {
            confidenceData = CVPixelBufferGetBaseAddress(conf)?.assumingMemoryBound(to: UInt8.self)
        }

        // Create output buffers
        var fusedBuffer: CVPixelBuffer?
        var confBuffer: CVPixelBuffer?

        CVPixelBufferCreate(kCFAllocatorDefault, outputWidth, outputHeight,
                          kCVPixelFormatType_DepthFloat32, nil, &fusedBuffer)
        CVPixelBufferCreate(kCFAllocatorDefault, outputWidth, outputHeight,
                          kCVPixelFormatType_OneComponent8, nil, &confBuffer)

        guard let fused = fusedBuffer, let conf = confBuffer else {
            throw DepthFusionError.bufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(fused, [])
        CVPixelBufferLockBaseAddress(conf, [])
        defer {
            CVPixelBufferUnlockBaseAddress(fused, [])
            CVPixelBufferUnlockBaseAddress(conf, [])
        }

        guard let fusedBase = CVPixelBufferGetBaseAddress(fused),
              let confBase = CVPixelBufferGetBaseAddress(conf) else {
            throw DepthFusionError.bufferAccessFailed
        }

        let fusedData = fusedBase.assumingMemoryBound(to: Float32.self)
        let outputConfData = confBase.assumingMemoryBound(to: UInt8.self)

        // Scale factors for coordinate mapping
        let scaleX = Float(lidarWidth) / Float(outputWidth)
        let scaleY = Float(lidarHeight) / Float(outputHeight)

        var validLidarCount = 0
        var aiFilledCount = 0
        let totalPixels = outputWidth * outputHeight

        // Fusion loop
        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let outIdx = y * outputWidth + x

                // Map to LiDAR coordinates (with bilinear sampling)
                let lxf = Float(x) * scaleX
                let lyf = Float(y) * scaleY
                let lx = Int(lxf)
                let ly = Int(lyf)

                // Get AI depth at this pixel
                let aiVal = aiData[outIdx]

                // Bilinear interpolation of LiDAR depth
                var lidarVal: Float = 0
                var lidarConf: Float = 0

                if lx >= 0 && lx < lidarWidth - 1 && ly >= 0 && ly < lidarHeight - 1 {
                    let fx = lxf - Float(lx)
                    let fy = lyf - Float(ly)

                    // Sample 4 neighbors
                    let d00 = lidarData[ly * lidarWidth + lx]
                    let d10 = lidarData[ly * lidarWidth + lx + 1]
                    let d01 = lidarData[(ly + 1) * lidarWidth + lx]
                    let d11 = lidarData[(ly + 1) * lidarWidth + lx + 1]

                    // Check validity
                    let validCount = [d00, d10, d01, d11].filter { $0 > 0.1 && $0 < 5.0 }.count

                    if validCount >= 3 {
                        // Bilinear interpolation
                        lidarVal = (1-fx)*(1-fy)*d00 + fx*(1-fy)*d10 +
                                   (1-fx)*fy*d01 + fx*fy*d11

                        // Get confidence
                        if let confPtr = confidenceData {
                            let c00 = Float(confPtr[ly * lidarWidth + lx]) / 2.0
                            let c10 = Float(confPtr[ly * lidarWidth + lx + 1]) / 2.0
                            let c01 = Float(confPtr[(ly + 1) * lidarWidth + lx]) / 2.0
                            let c11 = Float(confPtr[(ly + 1) * lidarWidth + lx + 1]) / 2.0
                            lidarConf = (1-fx)*(1-fy)*c00 + fx*(1-fy)*c10 +
                                       (1-fx)*fy*c01 + fx*fy*c11
                        } else {
                            lidarConf = validCount >= 4 ? 1.0 : 0.5
                        }
                    }
                }

                // Fusion logic
                let isLidarValid = lidarVal > 0.1 && lidarVal < 5.0
                let isAiValid = aiVal > 0.1 && aiVal < 5.0

                var fusedVal: Float = 0
                var fusedConf: UInt8 = 0

                if isLidarValid && isAiValid {
                    // Both valid - weighted fusion based on confidence
                    let w_lidar = lidarConf >= configuration.lidarConfidenceThreshold ?
                        configuration.lidarWeight : configuration.lidarWeight * 0.5
                    let w_ai = 1.0 - w_lidar

                    fusedVal = w_lidar * lidarVal + w_ai * aiVal
                    fusedConf = UInt8(min(255, (lidarConf * 0.6 + 0.4) * 255))
                    validLidarCount += 1
                } else if isLidarValid {
                    // Only LiDAR valid
                    fusedVal = lidarVal
                    fusedConf = UInt8(min(255, lidarConf * 255))
                    validLidarCount += 1
                } else if isAiValid {
                    // Only AI valid - fill holes
                    fusedVal = aiVal
                    fusedConf = UInt8(min(255, configuration.aiWeight * 128))
                    aiFilledCount += 1
                }

                fusedData[outIdx] = fusedVal
                outputConfData[outIdx] = fusedConf
            }
        }

        let lidarCoverage = Float(validLidarCount) / Float(totalPixels)
        let aiContribution = Float(aiFilledCount) / Float(totalPixels)

        return (fused, conf, (lidarCoverage, aiContribution))
    }

    // MARK: - Edge Detection

    private func detectDepthEdges(in depthBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }
        let depthData = baseAddress.assumingMemoryBound(to: Float32.self)

        // Create edge output buffer
        var edgeBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                          kCVPixelFormatType_OneComponent8, nil, &edgeBuffer)

        guard let edge = edgeBuffer else { return nil }

        CVPixelBufferLockBaseAddress(edge, [])
        defer { CVPixelBufferUnlockBaseAddress(edge, []) }

        guard let edgeBase = CVPixelBufferGetBaseAddress(edge) else { return nil }
        let edgeData = edgeBase.assumingMemoryBound(to: UInt8.self)

        // Sobel edge detection
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x

                // Sobel gradients
                let gx = -depthData[(y-1)*width + (x-1)] + depthData[(y-1)*width + (x+1)]
                       - 2*depthData[y*width + (x-1)] + 2*depthData[y*width + (x+1)]
                       - depthData[(y+1)*width + (x-1)] + depthData[(y+1)*width + (x+1)]

                let gy = -depthData[(y-1)*width + (x-1)] - 2*depthData[(y-1)*width + x] - depthData[(y-1)*width + (x+1)]
                       + depthData[(y+1)*width + (x-1)] + 2*depthData[(y+1)*width + x] + depthData[(y+1)*width + (x+1)]

                let magnitude = sqrt(gx*gx + gy*gy)

                // Threshold for edge
                edgeData[idx] = magnitude > configuration.edgeThreshold ? 255 : 0
            }
        }

        return edge
    }

    private func countEdgePixels(_ buffer: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let data = base.assumingMemoryBound(to: UInt8.self)

        var count = 0
        for i in 0..<(width * height) {
            if data[i] > 0 { count += 1 }
        }
        return count
    }

    // MARK: - Fallback

    private func createFallbackResult(
        lidarDepth: CVPixelBuffer,
        lidarConfidence: CVPixelBuffer?,
        startTime: CFTimeInterval
    ) throws -> FusionResult {
        // Just upscale LiDAR using bilinear interpolation
        CVPixelBufferLockBaseAddress(lidarDepth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(lidarDepth, .readOnly) }

        let lidarWidth = CVPixelBufferGetWidth(lidarDepth)
        let lidarHeight = CVPixelBufferGetHeight(lidarDepth)
        let outputWidth = lidarWidth * configuration.resolutionMultiplier
        let outputHeight = lidarHeight * configuration.resolutionMultiplier

        guard let lidarBase = CVPixelBufferGetBaseAddress(lidarDepth) else {
            throw DepthFusionError.bufferAccessFailed
        }

        let lidarData = lidarBase.assumingMemoryBound(to: Float32.self)

        // Create output buffer
        var outputBuffer: CVPixelBuffer?
        var confBuffer: CVPixelBuffer?

        CVPixelBufferCreate(kCFAllocatorDefault, outputWidth, outputHeight,
                          kCVPixelFormatType_DepthFloat32, nil, &outputBuffer)
        CVPixelBufferCreate(kCFAllocatorDefault, outputWidth, outputHeight,
                          kCVPixelFormatType_OneComponent8, nil, &confBuffer)

        guard let output = outputBuffer, let conf = confBuffer else {
            throw DepthFusionError.bufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(output, [])
        CVPixelBufferLockBaseAddress(conf, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(conf, [])
        }

        guard let outBase = CVPixelBufferGetBaseAddress(output),
              let confBase = CVPixelBufferGetBaseAddress(conf) else {
            throw DepthFusionError.bufferAccessFailed
        }

        let outData = outBase.assumingMemoryBound(to: Float32.self)
        let confData = confBase.assumingMemoryBound(to: UInt8.self)

        let scaleX = Float(lidarWidth - 1) / Float(outputWidth - 1)
        let scaleY = Float(lidarHeight - 1) / Float(outputHeight - 1)

        var validCount = 0

        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let outIdx = y * outputWidth + x

                let lxf = Float(x) * scaleX
                let lyf = Float(y) * scaleY
                let lx = Int(lxf)
                let ly = Int(lyf)
                let fx = lxf - Float(lx)
                let fy = lyf - Float(ly)

                let lx1 = min(lx + 1, lidarWidth - 1)
                let ly1 = min(ly + 1, lidarHeight - 1)

                let d00 = lidarData[ly * lidarWidth + lx]
                let d10 = lidarData[ly * lidarWidth + lx1]
                let d01 = lidarData[ly1 * lidarWidth + lx]
                let d11 = lidarData[ly1 * lidarWidth + lx1]

                let interpolated = (1-fx)*(1-fy)*d00 + fx*(1-fy)*d10 +
                                  (1-fx)*fy*d01 + fx*fy*d11

                outData[outIdx] = interpolated

                if interpolated > 0.1 && interpolated < 5.0 {
                    validCount += 1
                    confData[outIdx] = 200
                } else {
                    confData[outIdx] = 0
                }
            }
        }

        let processingTime = (CACurrentMediaTime() - startTime) * 1000

        return FusionResult(
            fusedDepth: output,
            confidenceMap: conf,
            edgeMap: nil,
            lidarResolution: CGSize(width: lidarWidth, height: lidarHeight),
            outputResolution: CGSize(width: outputWidth, height: outputHeight),
            stats: FusionStats(
                lidarCoverage: Float(validCount) / Float(outputWidth * outputHeight),
                aiContribution: 0,
                edgePixels: 0,
                processingTimeMs: processingTime
            )
        )
    }
}

// MARK: - Errors

enum DepthFusionError: LocalizedError {
    case noDepthData
    case bufferAccessFailed
    case bufferCreationFailed
    case fusionFailed

    var errorDescription: String? {
        switch self {
        case .noDepthData:
            return "No depth data available in ARFrame"
        case .bufferAccessFailed:
            return "Failed to access pixel buffer"
        case .bufferCreationFailed:
            return "Failed to create output buffer"
        case .fusionFailed:
            return "Depth fusion failed"
        }
    }
}
