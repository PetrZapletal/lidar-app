import AVFoundation
import CoreImage
import UIKit
import ARKit
import Combine

/// Production camera service for capturing texture frames from ARFrame for LRAW export
@MainActor
@Observable
final class CameraService: CameraServiceProtocol {

    // MARK: - Protocol Properties

    private(set) var isCapturing: Bool = false
    private(set) var capturedFrameCount: Int = 0

    // MARK: - Configuration

    struct Configuration {
        var compressionQuality: CGFloat = 0.85
        var maxFrameRate: Int = 30
        var maxBufferSize: Int = 200
    }

    // MARK: - Internal State

    private let configuration: Configuration
    private var frameBuffer: [TextureFrame] = []
    private var lastCaptureTime: TimeInterval = 0
    private let ciContext: CIContext
    private let minCaptureInterval: TimeInterval

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        self.minCaptureInterval = 1.0 / Double(configuration.maxFrameRate)
        debugLog("CameraService initialized", category: .logCategoryAR)
    }

    // MARK: - Protocol Methods

    func startCapture() {
        isCapturing = true
        debugLog("Camera capture started", category: .logCategoryAR)
    }

    func stopCapture() {
        isCapturing = false
        debugLog("Camera capture stopped, total frames: \(capturedFrameCount)", category: .logCategoryAR)
    }

    func getTextureFrames() -> [TextureFrame] {
        frameBuffer
    }

    func clearBuffer() {
        frameBuffer.removeAll()
        capturedFrameCount = 0
        lastCaptureTime = 0
        debugLog("Camera frame buffer cleared", category: .logCategoryAR)
    }

    // MARK: - Frame Processing

    /// Process an AR frame and capture texture data if conditions are met
    func processARFrame(_ frame: ARFrame) {
        guard isCapturing else { return }

        // Rate limiting
        let currentTime = frame.timestamp
        guard currentTime - lastCaptureTime >= minCaptureInterval else { return }

        // Only capture when tracking is good
        guard case .normal = frame.camera.trackingState else { return }

        guard let textureFrame = captureTextureFrame(from: frame) else { return }

        frameBuffer.append(textureFrame)
        capturedFrameCount += 1
        lastCaptureTime = currentTime

        // Enforce buffer size limit
        if frameBuffer.count > configuration.maxBufferSize {
            let excess = frameBuffer.count - configuration.maxBufferSize
            frameBuffer.removeFirst(excess)
        }
    }

    // MARK: - Private Methods

    private func captureTextureFrame(from frame: ARFrame) -> TextureFrame? {
        let capturedImage = frame.capturedImage
        let camera = frame.camera

        guard let imageData = compressPixelBuffer(capturedImage) else {
            warningLog("Failed to compress camera frame", category: .logCategoryAR)
            return nil
        }

        return TextureFrame(
            timestamp: frame.timestamp,
            imageData: imageData,
            resolution: camera.imageResolution,
            intrinsics: camera.intrinsics,
            cameraTransform: camera.transform,
            exposureDuration: frame.lightEstimate.map { Double($0.ambientIntensity) },
            iso: nil
        )
    }

    private func compressPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let uiImage = UIImage(cgImage: cgImage)

        // Try HEIC first, fall back to JPEG
        if let heicData = compressToHEIC(uiImage) {
            return heicData
        }
        return uiImage.jpegData(compressionQuality: configuration.compressionQuality)
    }

    private func compressToHEIC(_ image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.heic" as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: configuration.compressionQuality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}
