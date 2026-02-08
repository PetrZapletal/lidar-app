import AVFoundation
import CoreImage
import UIKit
import ARKit

/// Captures high-resolution camera frames synchronized with LiDAR data
final class CameraFrameCapture: Sendable {

    // MARK: - Configuration

    struct Configuration: Sendable {
        var captureQuality: CaptureQuality = .high
        var maxFrameRate: Int = 30
        var compressionQuality: CGFloat = 0.85
        var outputFormat: OutputFormat = .heic
        var includeMetadata: Bool = true

        enum CaptureQuality: Sendable {
            case low       // 720p
            case medium    // 1080p
            case high      // 4K
            case maximum   // Native resolution

            var targetResolution: CGSize {
                switch self {
                case .low: return CGSize(width: 1280, height: 720)
                case .medium: return CGSize(width: 1920, height: 1080)
                case .high: return CGSize(width: 3840, height: 2160)
                case .maximum: return .zero  // Use native
                }
            }
        }

        enum OutputFormat: Sendable {
            case heic
            case jpeg
            case png

            var utType: String {
                switch self {
                case .heic: return "public.heic"
                case .jpeg: return "public.jpeg"
                case .png: return "public.png"
                }
            }

            var fileExtension: String {
                switch self {
                case .heic: return "heic"
                case .jpeg: return "jpg"
                case .png: return "png"
                }
            }
        }
    }

    // MARK: - Captured Frame

    struct CapturedFrame: Sendable {
        let pixelBuffer: CVPixelBuffer
        let timestamp: TimeInterval
        let cameraTransform: simd_float4x4
        let cameraIntrinsics: simd_float3x3
        let imageResolution: CGSize
        let exposureDuration: TimeInterval
        let iso: Float

        var aspectRatio: CGFloat {
            imageResolution.width / imageResolution.height
        }
    }

    // MARK: - Frame Metadata

    struct FrameMetadata: Codable, Sendable {
        let timestamp: TimeInterval
        let cameraTransform: [Float]
        let intrinsics: [Float]
        let resolution: [Int]
        let exposureDuration: TimeInterval
        let iso: Float
        let focalLength: Float
        let principalPoint: [Float]

        init(from frame: CapturedFrame, camera: ARCamera) {
            self.timestamp = frame.timestamp
            self.cameraTransform = frame.cameraTransform.array
            self.intrinsics = frame.cameraIntrinsics.array
            self.resolution = [Int(frame.imageResolution.width), Int(frame.imageResolution.height)]
            self.exposureDuration = frame.exposureDuration
            self.iso = frame.iso
            self.focalLength = camera.intrinsics[0, 0]
            self.principalPoint = [camera.intrinsics[2, 0], camera.intrinsics[2, 1]]
        }
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let ciContext: CIContext

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: true
        ])
    }

    // MARK: - Frame Capture

    /// Capture frame from AR session
    func captureFrame(from arFrame: ARFrame) -> CapturedFrame {
        let camera = arFrame.camera

        return CapturedFrame(
            pixelBuffer: arFrame.capturedImage,
            timestamp: arFrame.timestamp,
            cameraTransform: camera.transform,
            cameraIntrinsics: camera.intrinsics,
            imageResolution: camera.imageResolution,
            exposureDuration: Double(arFrame.lightEstimate?.ambientIntensity ?? 0),
            iso: 100  // ARKit doesn't expose ISO directly
        )
    }

    /// Capture high-quality frame with optional resizing
    func captureHighQualityFrame(from arFrame: ARFrame) -> CapturedFrame? {
        let capturedImage = arFrame.capturedImage
        let camera = arFrame.camera

        // Check if resizing is needed
        let targetResolution = configuration.captureQuality.targetResolution
        let currentWidth = CVPixelBufferGetWidth(capturedImage)
        let currentHeight = CVPixelBufferGetHeight(capturedImage)

        if targetResolution != .zero &&
           (CGFloat(currentWidth) > targetResolution.width ||
            CGFloat(currentHeight) > targetResolution.height) {
            // Would need to resize - for now return original
            // Resizing can be implemented with CIImage if needed
        }

        return CapturedFrame(
            pixelBuffer: capturedImage,
            timestamp: arFrame.timestamp,
            cameraTransform: camera.transform,
            cameraIntrinsics: camera.intrinsics,
            imageResolution: camera.imageResolution,
            exposureDuration: Double(arFrame.lightEstimate?.ambientIntensity ?? 0),
            iso: 100
        )
    }

    // MARK: - Image Conversion

    /// Convert pixel buffer to UIImage
    func convertToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Convert pixel buffer to compressed data
    func compressFrame(_ frame: CapturedFrame) -> Data? {
        guard let uiImage = convertToUIImage(frame.pixelBuffer) else {
            return nil
        }

        switch configuration.outputFormat {
        case .heic:
            return compressToHEIC(uiImage)
        case .jpeg:
            return uiImage.jpegData(compressionQuality: configuration.compressionQuality)
        case .png:
            return uiImage.pngData()
        }
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
            // Fallback to JPEG if HEIC not supported
            return image.jpegData(compressionQuality: configuration.compressionQuality)
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: configuration.compressionQuality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return image.jpegData(compressionQuality: configuration.compressionQuality)
        }

        return data as Data
    }

    // MARK: - Metadata Generation

    /// Generate metadata for a captured frame
    func generateMetadata(for frame: CapturedFrame, camera: ARCamera) -> FrameMetadata {
        FrameMetadata(from: frame, camera: camera)
    }

    // MARK: - Batch Operations

    /// Process multiple frames for export
    func processFramesForExport(
        _ frames: [CapturedFrame],
        outputDirectory: URL
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        var outputURLs: [URL] = []

        for (index, frame) in frames.enumerated() {
            let filename = String(format: "frame_%05d.%@", index, configuration.outputFormat.fileExtension)
            let fileURL = outputDirectory.appendingPathComponent(filename)

            if let data = compressFrame(frame) {
                try data.write(to: fileURL)
                outputURLs.append(fileURL)
            }
        }

        return outputURLs
    }

    /// Export frames with metadata
    func exportFramesWithMetadata(
        _ frames: [(frame: CapturedFrame, camera: ARCamera)],
        outputDirectory: URL
    ) async throws -> (images: [URL], metadata: URL) {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        var imageURLs: [URL] = []
        var allMetadata: [FrameMetadata] = []

        for (index, item) in frames.enumerated() {
            // Save image
            let filename = String(format: "frame_%05d.%@", index, configuration.outputFormat.fileExtension)
            let fileURL = outputDirectory.appendingPathComponent(filename)

            if let data = compressFrame(item.frame) {
                try data.write(to: fileURL)
                imageURLs.append(fileURL)
            }

            // Collect metadata
            let metadata = generateMetadata(for: item.frame, camera: item.camera)
            allMetadata.append(metadata)
        }

        // Save metadata JSON
        let metadataURL = outputDirectory.appendingPathComponent("frames_metadata.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(allMetadata)
        try metadataData.write(to: metadataURL)

        return (imageURLs, metadataURL)
    }
}

// MARK: - Color Space Utilities

extension CameraFrameCapture {

    /// Extract RGB values at a specific point
    func sampleColor(from pixelBuffer: CVPixelBuffer, at point: CGPoint) -> (r: Float, g: Float, b: Float)? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let x = Int(point.x * CGFloat(width))
        let y = Int(point.y * CGFloat(height))

        guard x >= 0 && x < width && y >= 0 && y < height else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        if pixelFormat == kCVPixelFormatType_32BGRA {
            let offset = y * bytesPerRow + x * 4
            let pixel = baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            return (
                r: Float(pixel[2]) / 255.0,
                g: Float(pixel[1]) / 255.0,
                b: Float(pixel[0]) / 255.0
            )
        }

        // For YCbCr formats (common in ARKit), would need conversion
        return nil
    }

    /// Calculate average brightness of frame
    func calculateAverageBrightness(from pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Sample every 10th pixel for performance
        let stride = 10
        var sum: Float = 0
        var count = 0

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            // Y plane gives luminance directly
            guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
                return 0.5
            }

            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yData = yPlane.assumingMemoryBound(to: UInt8.self)

            for y in Swift.stride(from: 0, to: height, by: stride) {
                for x in Swift.stride(from: 0, to: width, by: stride) {
                    let offset = y * yBytesPerRow + x
                    sum += Float(yData[offset]) / 255.0
                    count += 1
                }
            }
        }

        return count > 0 ? sum / Float(count) : 0.5
    }
}

// MARK: - Matrix Array Extensions

private extension simd_float4x4 {
    var array: [Float] {
        [
            columns.0.x, columns.0.y, columns.0.z, columns.0.w,
            columns.1.x, columns.1.y, columns.1.z, columns.1.w,
            columns.2.x, columns.2.y, columns.2.z, columns.2.w,
            columns.3.x, columns.3.y, columns.3.z, columns.3.w
        ]
    }
}

private extension simd_float3x3 {
    var array: [Float] {
        [
            columns.0.x, columns.0.y, columns.0.z,
            columns.1.x, columns.1.y, columns.1.z,
            columns.2.x, columns.2.y, columns.2.z
        ]
    }
}
