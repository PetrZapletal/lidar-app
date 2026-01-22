import Foundation
import ARKit
import simd

// MARK: - Raw Data Package Format

/// Binary format for raw scan data:
/// ```
/// Header (32 bytes):
///   - Magic: "LRAW" (4 bytes)
///   - Version: UInt16 (2 bytes)
///   - Flags: UInt16 (2 bytes)
///   - Mesh anchor count: UInt32 (4 bytes)
///   - Texture frame count: UInt32 (4 bytes)
///   - Depth frame count: UInt32 (4 bytes)
///   - Reserved: 12 bytes
///
/// Mesh Anchors Section:
///   For each anchor:
///     - UUID: 16 bytes
///     - Transform: 64 bytes (16 floats)
///     - Vertex count: UInt32
///     - Face count: UInt32
///     - Classification flag: UInt8
///     - Vertices: [simd_float3]
///     - Normals: [simd_float3]
///     - Faces: [simd_uint3]
///     - Classifications: [UInt8] (optional)
///
/// Texture Frames Section:
///   For each frame:
///     - UUID: 16 bytes
///     - Timestamp: Double (8 bytes)
///     - Transform: 64 bytes
///     - Intrinsics: 36 bytes
///     - Image data length: UInt32
///     - Image data: JPEG/HEIC bytes
///
/// Depth Frames Section:
///   For each frame:
///     - UUID: 16 bytes
///     - Timestamp: Double (8 bytes)
///     - Transform: 64 bytes
///     - Intrinsics: 36 bytes
///     - Width/Height: 8 bytes
///     - Depth values: [Float32]
///     - Confidence values: [UInt8] (optional)
/// ```

struct RawDataPackager {

    // MARK: - Constants

    static let magic: [UInt8] = [0x4C, 0x52, 0x41, 0x57] // "LRAW"
    static let version: UInt16 = 1
    static let headerSize = 32

    // MARK: - Flags

    struct Flags: OptionSet {
        let rawValue: UInt16

        static let hasClassifications = Flags(rawValue: 1 << 0)
        static let hasConfidenceMaps = Flags(rawValue: 1 << 1)
        static let hasTextureFrames = Flags(rawValue: 1 << 2)
        static let hasDepthFrames = Flags(rawValue: 1 << 3)
        static let compressed = Flags(rawValue: 1 << 4)
    }

    // MARK: - Package Scan to File

    /// Configuration for packaging
    struct PackageConfiguration: Sendable {
        let includeConfidenceMaps: Bool
        let textureQuality: Double

        init(includeConfidenceMaps: Bool = true, textureQuality: Double = 0.95) {
            self.includeConfidenceMaps = includeConfidenceMaps
            self.textureQuality = textureQuality
        }

        @MainActor
        static func from(settings: DebugSettings) -> PackageConfiguration {
            PackageConfiguration(
                includeConfidenceMaps: settings.includeConfidenceMaps,
                textureQuality: settings.textureQuality
            )
        }
    }

    /// Package complete scan data to a temporary file
    /// Returns URL to the packaged file
    static func packageScan(
        meshAnchors: [ARMeshAnchor],
        textureFrames: [TextureFrame],
        depthFrames: [DepthFrame],
        configuration: PackageConfiguration = PackageConfiguration()
    ) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("raw_scan_\(UUID().uuidString).lraw")

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }

        // Determine flags
        var flags: Flags = []
        let hasClassifications = meshAnchors.contains { anchor in
            anchor.geometry.classification != nil
        }
        if hasClassifications { flags.insert(.hasClassifications) }
        if !textureFrames.isEmpty { flags.insert(.hasTextureFrames) }
        if !depthFrames.isEmpty { flags.insert(.hasDepthFrames) }
        if configuration.includeConfidenceMaps && depthFrames.contains(where: { $0.confidenceValues != nil }) {
            flags.insert(.hasConfidenceMaps)
        }

        // Write header
        try writeHeader(
            to: handle,
            flags: flags,
            meshCount: UInt32(meshAnchors.count),
            textureCount: UInt32(textureFrames.count),
            depthCount: UInt32(depthFrames.count)
        )

        // Write mesh anchors
        for anchor in meshAnchors {
            try writeMeshAnchor(anchor, to: handle, includeClassifications: hasClassifications)
        }

        // Write texture frames
        for frame in textureFrames {
            try writeTextureFrame(frame, to: handle, quality: configuration.textureQuality)
        }

        // Write depth frames
        for frame in depthFrames {
            try writeDepthFrame(frame, to: handle, includeConfidence: configuration.includeConfidenceMaps)
        }

        return tempURL
    }

    // MARK: - Header Writing

    static func writeHeader(
        to handle: FileHandle,
        flags: Flags,
        meshCount: UInt32,
        textureCount: UInt32,
        depthCount: UInt32
    ) throws {
        var header = Data(capacity: headerSize)

        // Magic (4 bytes)
        header.append(contentsOf: magic)

        // Version (2 bytes)
        var ver = version
        withUnsafeBytes(of: &ver) { header.append(contentsOf: $0) }

        // Flags (2 bytes)
        var fl = flags.rawValue
        withUnsafeBytes(of: &fl) { header.append(contentsOf: $0) }

        // Mesh count (4 bytes)
        var mc = meshCount
        withUnsafeBytes(of: &mc) { header.append(contentsOf: $0) }

        // Texture count (4 bytes)
        var tc = textureCount
        withUnsafeBytes(of: &tc) { header.append(contentsOf: $0) }

        // Depth count (4 bytes)
        var dc = depthCount
        withUnsafeBytes(of: &dc) { header.append(contentsOf: $0) }

        // Reserved (12 bytes)
        header.append(Data(count: 12))

        try handle.write(contentsOf: header)
    }

    // MARK: - Mesh Anchor Writing

    static func writeMeshAnchor(
        _ anchor: ARMeshAnchor,
        to handle: FileHandle,
        includeClassifications: Bool
    ) throws {
        var data = Data()

        let geometry = anchor.geometry

        // UUID (16 bytes)
        withUnsafeBytes(of: anchor.identifier.uuid) { data.append(contentsOf: $0) }

        // Transform (64 bytes)
        var transform = anchor.transform
        withUnsafeBytes(of: &transform) { data.append(contentsOf: $0) }

        // Vertex count (4 bytes)
        var vertexCount = UInt32(geometry.vertices.count)
        withUnsafeBytes(of: &vertexCount) { data.append(contentsOf: $0) }

        // Face count (4 bytes)
        var faceCount = UInt32(geometry.faces.count)
        withUnsafeBytes(of: &faceCount) { data.append(contentsOf: $0) }

        // Classification flag (1 byte)
        let hasClassification: UInt8 = (includeClassifications && geometry.classification != nil) ? 1 : 0
        data.append(hasClassification)

        // Vertices
        let vertexBuffer = geometry.vertices
        let vertexPointer = vertexBuffer.buffer.contents().advanced(by: vertexBuffer.offset)
        let vertices = vertexPointer.assumingMemoryBound(to: simd_float3.self)
        for i in 0..<vertexBuffer.count {
            var vertex = vertices[i]
            withUnsafeBytes(of: &vertex) { data.append(contentsOf: $0) }
        }

        // Normals
        let normalBuffer = geometry.normals
        let normalPointer = normalBuffer.buffer.contents().advanced(by: normalBuffer.offset)
        let normals = normalPointer.assumingMemoryBound(to: simd_float3.self)
        for i in 0..<normalBuffer.count {
            var normal = normals[i]
            withUnsafeBytes(of: &normal) { data.append(contentsOf: $0) }
        }

        // Faces
        let faceBuffer = geometry.faces
        let facePointer = faceBuffer.buffer.contents()

        // ARMeshGeometry faces are stored as Int32 indices
        if faceBuffer.bytesPerIndex == 4 {
            let indices = facePointer.assumingMemoryBound(to: Int32.self)
            for i in stride(from: 0, to: faceBuffer.count * 3, by: 3) {
                var face = simd_uint3(UInt32(indices[i]), UInt32(indices[i+1]), UInt32(indices[i+2]))
                withUnsafeBytes(of: &face) { data.append(contentsOf: $0) }
            }
        } else if faceBuffer.bytesPerIndex == 2 {
            let indices = facePointer.assumingMemoryBound(to: UInt16.self)
            for i in stride(from: 0, to: faceBuffer.count * 3, by: 3) {
                var face = simd_uint3(UInt32(indices[i]), UInt32(indices[i+1]), UInt32(indices[i+2]))
                withUnsafeBytes(of: &face) { data.append(contentsOf: $0) }
            }
        }

        // Classifications (if present)
        if hasClassification == 1, let classification = geometry.classification {
            let classPointer = classification.buffer.contents().advanced(by: classification.offset)
            let classes = classPointer.assumingMemoryBound(to: UInt8.self)
            for i in 0..<classification.count {
                data.append(classes[i])
            }
        }

        try handle.write(contentsOf: data)
    }

    // MARK: - Texture Frame Writing

    static func writeTextureFrame(
        _ frame: TextureFrame,
        to handle: FileHandle,
        quality: Double
    ) throws {
        var data = Data()

        // UUID (16 bytes)
        withUnsafeBytes(of: frame.id.uuid) { data.append(contentsOf: $0) }

        // Timestamp (8 bytes)
        var timestamp = frame.timestamp
        withUnsafeBytes(of: &timestamp) { data.append(contentsOf: $0) }

        // Transform (64 bytes)
        var transform = frame.cameraTransform
        withUnsafeBytes(of: &transform) { data.append(contentsOf: $0) }

        // Intrinsics (36 bytes)
        var intrinsics = frame.intrinsics
        withUnsafeBytes(of: &intrinsics) { data.append(contentsOf: $0) }

        // Resolution (8 bytes)
        var width = UInt32(frame.resolution.width)
        var height = UInt32(frame.resolution.height)
        withUnsafeBytes(of: &width) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &height) { data.append(contentsOf: $0) }

        // Re-compress image at specified quality if needed
        var imageData = frame.imageData
        if quality < 1.0, let image = UIImage(data: frame.imageData),
           let recompressed = image.jpegData(compressionQuality: quality) {
            imageData = recompressed
        }

        // Image data length (4 bytes)
        var imageLength = UInt32(imageData.count)
        withUnsafeBytes(of: &imageLength) { data.append(contentsOf: $0) }

        // Image data
        data.append(imageData)

        try handle.write(contentsOf: data)
    }

    // MARK: - Depth Frame Writing

    static func writeDepthFrame(
        _ frame: DepthFrame,
        to handle: FileHandle,
        includeConfidence: Bool
    ) throws {
        let data = frame.toBinaryData()
        try handle.write(contentsOf: data)
    }

    // MARK: - Metadata

    /// Generate JSON metadata for the raw package
    static func generateMetadata(
        scanId: UUID,
        sessionName: String,
        meshAnchors: [ARMeshAnchor],
        textureFrames: [TextureFrame],
        depthFrames: [DepthFrame],
        deviceInfo: [String: String]
    ) -> Data? {
        var totalVertices = 0
        var totalFaces = 0

        for anchor in meshAnchors {
            totalVertices += anchor.geometry.vertices.count
            totalFaces += anchor.geometry.faces.count
        }

        let metadata: [String: Any] = [
            "version": Int(version),
            "scanId": scanId.uuidString,
            "sessionName": sessionName,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "deviceInfo": deviceInfo,
            "statistics": [
                "meshAnchorCount": meshAnchors.count,
                "textureFrameCount": textureFrames.count,
                "depthFrameCount": depthFrames.count,
                "totalVertices": totalVertices,
                "totalFaces": totalFaces
            ]
        ]

        return try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
    }
}

// MARK: - TextureFrame Extension

extension TextureFrame {
    /// Create from ARFrame with compression quality
    static func capture(from frame: ARFrame, quality: CGFloat = 0.95) -> TextureFrame? {
        let pixelBuffer = frame.capturedImage

        // Convert CVPixelBuffer to UIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: quality) else {
            return nil
        }

        return TextureFrame(
            timestamp: frame.timestamp,
            imageData: jpegData,
            resolution: CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            ),
            intrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            exposureDuration: frame.camera.exposureDuration,
            iso: frame.camera.exposureOffset
        )
    }
}

// MARK: - Texture Frame Buffer

/// Thread-safe buffer for texture frames
actor TextureFrameBuffer {
    private var frames: [TextureFrame] = []
    private let maxFrames: Int
    private let captureInterval: Int

    private var frameCounter = 0

    init(maxFrames: Int = 500, captureInterval: Int = 10) {
        self.maxFrames = maxFrames
        self.captureInterval = captureInterval
    }

    func addFrame(_ frame: TextureFrame) -> Bool {
        frameCounter += 1

        guard frameCounter % captureInterval == 0 else {
            return false
        }

        guard frames.count < maxFrames else {
            return false
        }

        frames.append(frame)
        return true
    }

    func getAllFrames() -> [TextureFrame] {
        frames
    }

    var count: Int {
        frames.count
    }

    var totalSizeBytes: Int {
        frames.reduce(0) { $0 + $1.imageData.count }
    }

    func clear() {
        frames.removeAll()
        frameCounter = 0
    }
}
