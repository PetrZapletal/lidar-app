import CoreML
import Vision
import CoreImage
import Accelerate
import CoreVideo

/// Wrapper for DepthAnything V2 CoreML model providing monocular depth estimation.
///
/// Uses the Vision framework for inference and the Accelerate framework for
/// efficient post-processing of depth maps. The model accepts an RGB image
/// and produces a dense depth map output.
@MainActor
@Observable
final class DepthAnythingModel {

    // MARK: - Types

    enum ModelState: Equatable {
        case unloaded
        case loading
        case ready
        case error(String)

        static func == (lhs: ModelState, rhs: ModelState) -> Bool {
            switch (lhs, rhs) {
            case (.unloaded, .unloaded), (.loading, .loading), (.ready, .ready):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    private(set) var state: ModelState = .unloaded
    private var model: VNCoreMLModel?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Whether the model is ready for inference
    var isReady: Bool { state == .ready }

    // MARK: - Model Lifecycle

    /// Load the DepthAnything V2 CoreML model asynchronously.
    ///
    /// Configures the model to prefer the Apple Neural Engine for efficient
    /// on-device inference with CPU fallback.
    func loadModel() async {
        guard state != .loading && state != .ready else {
            debugLog("Model already \(state == .ready ? "loaded" : "loading"), skipping", category: .logCategoryML)
            return
        }

        state = .loading
        debugLog("Loading DepthAnything V2 model...", category: .logCategoryML)

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            let mlModel = try await DepthAnythingV2SmallF16.load(configuration: config)
            model = try VNCoreMLModel(for: mlModel.model)
            state = .ready
            infoLog("DepthAnything V2 model loaded successfully", category: .logCategoryML)
        } catch {
            let message = error.localizedDescription
            state = .error(message)
            errorLog("Failed to load DepthAnything model: \(message)", category: .logCategoryML)
        }
    }

    /// Run depth prediction on a CGImage.
    ///
    /// Uses the Vision framework to perform inference and extracts the resulting
    /// depth map as a CVPixelBuffer with Float32 depth values.
    ///
    /// - Parameter image: The input RGB image for depth estimation.
    /// - Returns: A CVPixelBuffer containing the predicted depth map.
    /// - Throws: `EdgeMLError` if the model is not loaded or inference fails.
    func predictDepth(from image: CGImage) async throws -> CVPixelBuffer {
        guard let model = model else {
            throw EdgeMLError.modelNotLoaded
        }

        debugLog("Running depth prediction on \(image.width)x\(image.height) image", category: .logCategoryML)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error = error {
                    continuation.resume(throwing: EdgeMLError.predictionFailed(error.localizedDescription))
                    return
                }

                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let firstResult = results.first,
                      let multiArray = firstResult.featureValue.multiArrayValue else {
                    continuation.resume(throwing: EdgeMLError.predictionFailed("No depth output from model"))
                    return
                }

                // Convert MLMultiArray to CVPixelBuffer
                do {
                    let depthBuffer = try self.multiArrayToPixelBuffer(multiArray)
                    continuation.resume(returning: depthBuffer)
                } catch {
                    continuation.resume(throwing: EdgeMLError.predictionFailed(
                        "Failed to convert model output: \(error.localizedDescription)"
                    ))
                }
            }

            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: EdgeMLError.predictionFailed(
                    "Vision request failed: \(error.localizedDescription)"
                ))
            }
        }
    }

    /// Convert a depth CVPixelBuffer to a normalized float array.
    ///
    /// Uses the Accelerate framework (vDSP) for efficient conversion and
    /// normalization of depth values to the [0, 1] range.
    ///
    /// - Parameter depthBuffer: The depth map pixel buffer to convert.
    /// - Returns: An array of normalized Float depth values.
    func depthMapToFloatArray(_ depthBuffer: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let count = width * height

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            warningLog("Failed to get base address from depth buffer", category: .logCategoryML)
            return []
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(depthBuffer)
        var result = [Float](repeating: 0, count: count)

        if pixelFormat == kCVPixelFormatType_DepthFloat32 {
            // Direct Float32 copy
            let sourcePointer = baseAddress.assumingMemoryBound(to: Float.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
            let floatsPerRow = bytesPerRow / MemoryLayout<Float>.stride

            for y in 0..<height {
                let rowStart = y * floatsPerRow
                let destStart = y * width
                for x in 0..<width {
                    result[destStart + x] = sourcePointer[rowStart + x]
                }
            }
        } else if pixelFormat == kCVPixelFormatType_OneComponent16Half {
            // Float16 to Float32 conversion using Accelerate
            let sourcePointer = baseAddress.assumingMemoryBound(to: UInt16.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
            let elementsPerRow = bytesPerRow / MemoryLayout<UInt16>.stride

            var halfValues = [UInt16](repeating: 0, count: count)
            for y in 0..<height {
                let rowStart = y * elementsPerRow
                let destStart = y * width
                for x in 0..<width {
                    halfValues[destStart + x] = sourcePointer[rowStart + x]
                }
            }

            halfValues.withUnsafeBufferPointer { halfPtr in
                var src = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: halfPtr.baseAddress!),
                    height: 1,
                    width: vImagePixelCount(count),
                    rowBytes: count * MemoryLayout<UInt16>.stride
                )
                result.withUnsafeMutableBufferPointer { floatPtr in
                    var dst = vImage_Buffer(
                        data: UnsafeMutableRawPointer(floatPtr.baseAddress!),
                        height: 1,
                        width: vImagePixelCount(count),
                        rowBytes: count * MemoryLayout<Float>.stride
                    )
                    vImageConvert_Planar16FtoPlanarF(&src, &dst, 0)
                }
            }
        } else {
            // Fallback: attempt to read as Float32
            warningLog("Unexpected pixel format \(pixelFormat), attempting Float32 read", category: .logCategoryML)
            let sourcePointer = baseAddress.assumingMemoryBound(to: Float.self)
            result = Array(UnsafeBufferPointer(start: sourcePointer, count: count))
        }

        // Normalize depth values to [0, 1] range using vDSP
        var minVal: Float = 0
        var maxVal: Float = 0
        vDSP_minv(result, 1, &minVal, vDSP_Length(count))
        vDSP_maxv(result, 1, &maxVal, vDSP_Length(count))

        let range = maxVal - minVal
        if range > .ulpOfOne {
            var negMin = -minVal
            vDSP_vsadd(result, 1, &negMin, &result, 1, vDSP_Length(count))
            var invRange = 1.0 / range
            vDSP_vsmul(result, 1, &invRange, &result, 1, vDSP_Length(count))
        }

        debugLog("Converted depth map \(width)x\(height), range [\(minVal), \(maxVal)]", category: .logCategoryML)
        return result
    }

    /// Unload the model from memory to free resources.
    func unloadModel() {
        model = nil
        state = .unloaded
        debugLog("DepthAnything model unloaded", category: .logCategoryML)
    }

    // MARK: - Private Helpers

    /// Convert an MLMultiArray depth output to a CVPixelBuffer.
    ///
    /// Handles both 3D (1 x H x W) and 2D (H x W) multi-array shapes,
    /// normalizing values to depth range during conversion.
    private func multiArrayToPixelBuffer(_ multiArray: MLMultiArray) throws -> CVPixelBuffer {
        let shape = multiArray.shape.map { $0.intValue }

        let height: Int
        let width: Int

        // DepthAnything outputs: [1, H, W] or [H, W]
        if shape.count == 3 {
            height = shape[1]
            width = shape[2]
        } else if shape.count == 2 {
            height = shape[0]
            width = shape[1]
        } else {
            throw EdgeMLError.predictionFailed(
                "Unexpected output shape: \(shape)"
            )
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let outputBuffer = pixelBuffer else {
            throw EdgeMLError.predictionFailed("Failed to create output pixel buffer")
        }

        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }

        guard let destBase = CVPixelBufferGetBaseAddress(outputBuffer) else {
            throw EdgeMLError.predictionFailed("Failed to get pixel buffer base address")
        }

        let destPointer = destBase.assumingMemoryBound(to: Float32.self)
        let totalElements = width * height
        let bytesPerRow = CVPixelBufferGetBytesPerRow(outputBuffer)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.stride

        // Extract values from MLMultiArray
        let dataPointer = multiArray.dataPointer.assumingMemoryBound(to: Float.self)

        if multiArray.dataType == .float32 {
            for y in 0..<height {
                for x in 0..<width {
                    let srcIndex = y * width + x
                    let destIndex = y * floatsPerRow + x
                    destPointer[destIndex] = dataPointer[srcIndex]
                }
            }
        } else {
            // Generic path: use subscript access for Float16/Double types
            for y in 0..<height {
                for x in 0..<width {
                    let srcIndex = y * width + x
                    let destIndex = y * floatsPerRow + x
                    if shape.count == 3 {
                        destPointer[destIndex] = multiArray[[0, y, x] as [NSNumber]].floatValue
                    } else {
                        destPointer[destIndex] = multiArray[[y, x] as [NSNumber]].floatValue
                    }
                }
            }
        }

        // Normalize depth values to positive range
        var values = [Float](repeating: 0, count: totalElements)
        for y in 0..<height {
            for x in 0..<width {
                values[y * width + x] = destPointer[y * floatsPerRow + x]
            }
        }

        var minVal: Float = 0
        var maxVal: Float = 0
        vDSP_minv(values, 1, &minVal, vDSP_Length(totalElements))
        vDSP_maxv(values, 1, &maxVal, vDSP_Length(totalElements))

        let range = maxVal - minVal
        if range > .ulpOfOne {
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * floatsPerRow + x
                    destPointer[idx] = (destPointer[idx] - minVal) / range
                }
            }
        }

        debugLog("Model output \(width)x\(height), value range [\(minVal), \(maxVal)]", category: .logCategoryML)
        return outputBuffer
    }
}
