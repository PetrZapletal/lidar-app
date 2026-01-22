import CoreML
import Vision
import CoreImage
import UIKit
import simd

/// CoreML wrapper for Depth Anything V2 model
/// Provides high-resolution monocular depth estimation
@MainActor
final class DepthAnythingModel {

    // MARK: - Configuration

    struct Configuration {
        /// Model input size (Depth Anything V2 Small uses 518x518)
        var inputSize: CGSize = CGSize(width: 518, height: 518)

        /// Whether to use Neural Engine when available
        var useNeuralEngine: Bool = true

        /// Normalize output to metric depth using reference
        var normalizeToMetric: Bool = true

        /// Minimum valid depth for normalization reference
        var minValidDepth: Float = 0.1

        /// Maximum valid depth for normalization reference
        var maxValidDepth: Float = 5.0
    }

    // MARK: - Model Output

    struct DepthPrediction {
        /// Relative depth map (normalized 0-1, closer = higher value)
        let relativeDepth: CVPixelBuffer

        /// Metric depth map (if normalized with LiDAR reference)
        let metricDepth: CVPixelBuffer?

        /// Original image size
        let originalSize: CGSize

        /// Prediction confidence (based on edge clarity)
        let confidence: Float

        /// Processing time in milliseconds
        let processingTimeMs: Double
    }

    // MARK: - Properties

    private let configuration: Configuration
    private var visionModel: VNCoreMLModel?
    private let ciContext: CIContext

    /// Model loading state
    private(set) var isLoaded: Bool = false
    private(set) var loadError: Error?

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: true
        ])
    }

    // MARK: - Model Loading

    /// Load the CoreML model
    func loadModel() async throws {
        // Try to load the model from bundle
        // Model should be added as DepthAnythingV2SmallF16.mlpackage (compiled to mlmodelc by Xcode)
        let modelNames = ["DepthAnythingV2SmallF16", "DepthAnythingV2Small"]
        var modelURL: URL?

        for name in modelNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                modelURL = url
                print("✅ Found model: \(name).mlmodelc")
                break
            }
        }

        guard let finalURL = modelURL else {
            // Model not found - use placeholder for development
            print("⚠️ Depth Anything V2 model not found in bundle")
            print("   Expected: DepthAnythingV2SmallF16.mlmodelc")
            print("   Download from: https://huggingface.co/apple/coreml-depth-anything-v2-small")
            loadError = DepthAnythingError.modelNotFound
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = configuration.useNeuralEngine ? .all : .cpuAndGPU

            let mlModel = try await MLModel.load(contentsOf: finalURL, configuration: config)
            visionModel = try VNCoreMLModel(for: mlModel)
            isLoaded = true

            print("✅ Depth Anything V2 model loaded successfully")
            print("   Compute units: \(configuration.useNeuralEngine ? "Neural Engine" : "CPU/GPU")")
        } catch {
            loadError = error
            throw DepthAnythingError.modelLoadFailed(error)
        }
    }

    // MARK: - Depth Prediction

    /// Predict depth from RGB image
    func predictDepth(from image: CVPixelBuffer) async throws -> DepthPrediction {
        let startTime = CACurrentMediaTime()

        guard let model = visionModel else {
            throw DepthAnythingError.modelNotLoaded
        }

        let imageWidth = CVPixelBufferGetWidth(image)
        let imageHeight = CVPixelBufferGetHeight(image)
        let originalSize = CGSize(width: imageWidth, height: imageHeight)

        // Create Vision request
        let request = VNCoreMLRequest(model: model) { _, _ in }
        request.imageCropAndScaleOption = .scaleFill

        // Run inference
        let handler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        try handler.perform([request])

        // Extract result
        guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
              let depthFeature = observations.first?.featureValue,
              let depthMultiArray = depthFeature.multiArrayValue else {
            throw DepthAnythingError.invalidOutput
        }

        // Convert MLMultiArray to CVPixelBuffer
        let relativeDepth = try convertToDepthBuffer(depthMultiArray, size: configuration.inputSize)

        // Calculate confidence based on depth variance
        let confidence = calculateConfidence(depthMultiArray)

        let processingTime = (CACurrentMediaTime() - startTime) * 1000

        return DepthPrediction(
            relativeDepth: relativeDepth,
            metricDepth: nil,
            originalSize: originalSize,
            confidence: confidence,
            processingTimeMs: processingTime
        )
    }

    /// Predict depth from UIImage
    func predictDepth(from image: UIImage) async throws -> DepthPrediction {
        guard let ciImage = CIImage(image: image) else {
            throw DepthAnythingError.invalidInput
        }

        // Create pixel buffer from CIImage
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(ciImage.extent.width),
            Int(ciImage.extent.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard let buffer = pixelBuffer else {
            throw DepthAnythingError.bufferCreationFailed
        }

        ciContext.render(ciImage, to: buffer)

        return try await predictDepth(from: buffer)
    }

    /// Predict metric depth by normalizing with LiDAR reference
    func predictMetricDepth(
        from image: CVPixelBuffer,
        lidarDepth: CVPixelBuffer,
        lidarConfidence: CVPixelBuffer?
    ) async throws -> DepthPrediction {
        // Get relative depth prediction
        var prediction = try await predictDepth(from: image)

        // Normalize to metric using LiDAR reference
        let metricDepth = try normalizeToMetric(
            relativeDepth: prediction.relativeDepth,
            lidarDepth: lidarDepth,
            lidarConfidence: lidarConfidence
        )

        return DepthPrediction(
            relativeDepth: prediction.relativeDepth,
            metricDepth: metricDepth,
            originalSize: prediction.originalSize,
            confidence: prediction.confidence,
            processingTimeMs: prediction.processingTimeMs
        )
    }

    // MARK: - Depth Normalization

    /// Convert relative depth to metric depth using LiDAR as reference
    private func normalizeToMetric(
        relativeDepth: CVPixelBuffer,
        lidarDepth: CVPixelBuffer,
        lidarConfidence: CVPixelBuffer?
    ) throws -> CVPixelBuffer {
        CVPixelBufferLockBaseAddress(relativeDepth, .readOnly)
        CVPixelBufferLockBaseAddress(lidarDepth, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(relativeDepth, .readOnly)
            CVPixelBufferUnlockBaseAddress(lidarDepth, .readOnly)
        }

        if let conf = lidarConfidence {
            CVPixelBufferLockBaseAddress(conf, .readOnly)
        }
        defer {
            if let conf = lidarConfidence {
                CVPixelBufferUnlockBaseAddress(conf, .readOnly)
            }
        }

        let aiWidth = CVPixelBufferGetWidth(relativeDepth)
        let aiHeight = CVPixelBufferGetHeight(relativeDepth)
        let lidarWidth = CVPixelBufferGetWidth(lidarDepth)
        let lidarHeight = CVPixelBufferGetHeight(lidarDepth)

        guard let aiBase = CVPixelBufferGetBaseAddress(relativeDepth),
              let lidarBase = CVPixelBufferGetBaseAddress(lidarDepth) else {
            throw DepthAnythingError.bufferAccessFailed
        }

        let aiData = aiBase.assumingMemoryBound(to: Float32.self)
        let lidarData = lidarBase.assumingMemoryBound(to: Float32.self)

        var confidenceData: UnsafeMutablePointer<UInt8>?
        if let conf = lidarConfidence {
            confidenceData = CVPixelBufferGetBaseAddress(conf)?.assumingMemoryBound(to: UInt8.self)
        }

        // Collect corresponding points for scale estimation
        var aiValues: [Float] = []
        var lidarValues: [Float] = []

        // Sample points where LiDAR has high confidence
        let sampleStride = 4
        for ly in stride(from: 0, to: lidarHeight, by: sampleStride) {
            for lx in stride(from: 0, to: lidarWidth, by: sampleStride) {
                let lidarIdx = ly * lidarWidth + lx
                let lidarVal = lidarData[lidarIdx]

                // Check validity
                guard lidarVal > configuration.minValidDepth &&
                      lidarVal < configuration.maxValidDepth else { continue }

                // Check confidence
                if let conf = confidenceData {
                    guard conf[lidarIdx] >= 1 else { continue } // Medium or high confidence
                }

                // Map to AI depth coordinates
                let ax = Int(Float(lx) * Float(aiWidth) / Float(lidarWidth))
                let ay = Int(Float(ly) * Float(aiHeight) / Float(lidarHeight))

                guard ax >= 0 && ax < aiWidth && ay >= 0 && ay < aiHeight else { continue }

                let aiIdx = ay * aiWidth + ax
                let aiVal = aiData[aiIdx]

                // AI depth is relative (0-1), needs to be inverted (closer = higher in AI)
                guard aiVal > 0.01 else { continue }

                aiValues.append(aiVal)
                lidarValues.append(lidarVal)
            }
        }

        // Calculate scale and offset using least squares
        guard aiValues.count >= 10 else {
            throw DepthAnythingError.insufficientReferencePoints
        }

        let (scale, offset) = calculateScaleOffset(
            aiValues: aiValues,
            lidarValues: lidarValues
        )

        // Create output buffer
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            aiWidth, aiHeight,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &outputBuffer
        )

        guard let output = outputBuffer else {
            throw DepthAnythingError.bufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        guard let outputBase = CVPixelBufferGetBaseAddress(output) else {
            throw DepthAnythingError.bufferAccessFailed
        }

        let outputData = outputBase.assumingMemoryBound(to: Float32.self)

        // Apply transformation: metric = 1 / (scale * relative + offset)
        // This handles the inversion (AI: closer = higher, metric: closer = lower)
        for i in 0..<(aiWidth * aiHeight) {
            let relVal = aiData[i]

            if relVal > 0.001 {
                // Convert relative to metric
                let metricVal = 1.0 / (scale * relVal + offset)

                // Clamp to valid range
                outputData[i] = max(configuration.minValidDepth,
                                   min(configuration.maxValidDepth, metricVal))
            } else {
                outputData[i] = 0 // Invalid
            }
        }

        return output
    }

    /// Calculate scale and offset for depth normalization
    private func calculateScaleOffset(
        aiValues: [Float],
        lidarValues: [Float]
    ) -> (scale: Float, offset: Float) {
        // We want to find scale, offset such that:
        // lidar = 1 / (scale * ai + offset)
        // Or: 1/lidar = scale * ai + offset

        let n = Float(aiValues.count)
        var sumAi: Float = 0
        var sumInvLidar: Float = 0
        var sumAiInvLidar: Float = 0
        var sumAiSq: Float = 0

        for i in 0..<aiValues.count {
            let ai = aiValues[i]
            let invLidar = 1.0 / lidarValues[i]

            sumAi += ai
            sumInvLidar += invLidar
            sumAiInvLidar += ai * invLidar
            sumAiSq += ai * ai
        }

        // Least squares: y = ax + b
        // a = (n*sum(xy) - sum(x)*sum(y)) / (n*sum(x²) - sum(x)²)
        // b = (sum(y) - a*sum(x)) / n

        let denominator = n * sumAiSq - sumAi * sumAi
        guard abs(denominator) > 1e-6 else {
            return (1.0, 0.0) // Fallback
        }

        let scale = (n * sumAiInvLidar - sumAi * sumInvLidar) / denominator
        let offset = (sumInvLidar - scale * sumAi) / n

        return (max(0.1, scale), max(0.001, offset))
    }

    // MARK: - Helper Methods

    /// Convert MLMultiArray to CVPixelBuffer depth format
    private func convertToDepthBuffer(_ array: MLMultiArray, size: CGSize) throws -> CVPixelBuffer {
        let width = Int(size.width)
        let height = Int(size.height)

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &buffer
        )

        guard let outputBuffer = buffer else {
            throw DepthAnythingError.bufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(outputBuffer) else {
            throw DepthAnythingError.bufferAccessFailed
        }

        let destData = baseAddress.assumingMemoryBound(to: Float32.self)
        let srcPointer = array.dataPointer.assumingMemoryBound(to: Float32.self)

        // Copy and normalize values to 0-1 range
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude

        for i in 0..<(width * height) {
            let val = srcPointer[i]
            minVal = min(minVal, val)
            maxVal = max(maxVal, val)
        }

        let range = maxVal - minVal
        for i in 0..<(width * height) {
            destData[i] = range > 0 ? (srcPointer[i] - minVal) / range : 0.5
        }

        return outputBuffer
    }

    /// Calculate prediction confidence from depth variance
    private func calculateConfidence(_ array: MLMultiArray) -> Float {
        let count = array.count
        let ptr = array.dataPointer.assumingMemoryBound(to: Float32.self)

        var sum: Float = 0
        var sumSq: Float = 0

        for i in 0..<count {
            let val = ptr[i]
            sum += val
            sumSq += val * val
        }

        let mean = sum / Float(count)
        let variance = sumSq / Float(count) - mean * mean

        // Higher variance = more confident depth structure
        // Normalize to 0-1 range
        return min(1.0, sqrt(variance) * 10)
    }
}

// MARK: - Errors

enum DepthAnythingError: LocalizedError {
    case modelNotFound
    case modelNotLoaded
    case modelLoadFailed(Error)
    case invalidInput
    case invalidOutput
    case bufferCreationFailed
    case bufferAccessFailed
    case insufficientReferencePoints

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Depth Anything V2 model not found in bundle"
        case .modelNotLoaded:
            return "Model not loaded. Call loadModel() first"
        case .modelLoadFailed(let error):
            return "Failed to load model: \(error.localizedDescription)"
        case .invalidInput:
            return "Invalid input image"
        case .invalidOutput:
            return "Invalid model output"
        case .bufferCreationFailed:
            return "Failed to create pixel buffer"
        case .bufferAccessFailed:
            return "Failed to access pixel buffer"
        case .insufficientReferencePoints:
            return "Insufficient reference points for depth normalization"
        }
    }
}

// MARK: - Depth Anything Model Info

extension DepthAnythingModel {

    /// Information about the model
    static var modelInfo: String {
        """
        Depth Anything V2 Small (F16)
        =============================
        - Input: 518×396 RGB image (4:3 aspect ratio)
        - Output: 518×396 relative depth map
        - Size: ~49MB (FP16 quantized)
        - Inference: 31ms on iPhone 12 Pro Max
        - Compute: Neural Engine optimized

        Source: https://huggingface.co/apple/coreml-depth-anything-v2-small

        Usage:
        1. Model is located at: ML/DepthAnythingV2SmallF16.mlpackage
        2. Xcode automatically compiles .mlpackage to .mlmodelc
        """
    }
}
