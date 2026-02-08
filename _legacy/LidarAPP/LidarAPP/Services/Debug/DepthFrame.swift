import Foundation
import ARKit
import simd

// MARK: - Depth Frame

/// Represents a captured depth frame with associated metadata
/// Used for raw data upload pipeline
struct DepthFrame: Identifiable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    let cameraTransform: simd_float4x4
    let cameraIntrinsics: simd_float3x3
    let width: Int
    let height: Int
    let depthValues: [Float]
    let confidenceValues: [UInt8]?

    /// Create from ARFrame's scene depth
    init?(from frame: ARFrame) {
        guard let sceneDepth = frame.sceneDepth ?? frame.smoothedSceneDepth else {
            return nil
        }

        self.id = UUID()
        self.timestamp = frame.timestamp
        self.cameraTransform = frame.camera.transform
        self.cameraIntrinsics = frame.camera.intrinsics

        // Extract depth values from CVPixelBuffer
        let depthMap = sceneDepth.depthMap
        self.width = CVPixelBufferGetWidth(depthMap)
        self.height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        var depths: [Float] = []
        depths.reserveCapacity(width * height)

        for y in 0..<height {
            let rowStart = baseAddress.advanced(by: y * bytesPerRow)
            let rowPointer = rowStart.assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                depths.append(rowPointer[x])
            }
        }
        self.depthValues = depths

        // Extract confidence values if available
        if let confidenceMap = sceneDepth.confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

            guard let confBaseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
                self.confidenceValues = nil
                return
            }

            let confBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
            let confWidth = CVPixelBufferGetWidth(confidenceMap)
            let confHeight = CVPixelBufferGetHeight(confidenceMap)

            var confidences: [UInt8] = []
            confidences.reserveCapacity(confWidth * confHeight)

            for y in 0..<confHeight {
                let rowStart = confBaseAddress.advanced(by: y * confBytesPerRow)
                let rowPointer = rowStart.assumingMemoryBound(to: UInt8.self)
                for x in 0..<confWidth {
                    confidences.append(rowPointer[x])
                }
            }
            self.confidenceValues = confidences
        } else {
            self.confidenceValues = nil
        }
    }

    /// Initialize with explicit values (for testing/deserialization)
    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        width: Int,
        height: Int,
        depthValues: [Float],
        confidenceValues: [UInt8]?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cameraTransform = cameraTransform
        self.cameraIntrinsics = cameraIntrinsics
        self.width = width
        self.height = height
        self.depthValues = depthValues
        self.confidenceValues = confidenceValues
    }

    // MARK: - Computed Properties

    /// Size in bytes for depth data only
    var depthDataSize: Int {
        depthValues.count * MemoryLayout<Float>.size
    }

    /// Size in bytes for confidence data
    var confidenceDataSize: Int {
        confidenceValues?.count ?? 0
    }

    /// Total size in bytes
    var totalSize: Int {
        // Header: id (16) + timestamp (8) + transform (64) + intrinsics (36) + dimensions (8)
        let headerSize = 16 + 8 + 64 + 36 + 8
        return headerSize + depthDataSize + confidenceDataSize
    }

    /// Average depth value
    var averageDepth: Float {
        guard !depthValues.isEmpty else { return 0 }
        let validDepths = depthValues.filter { $0.isFinite && $0 > 0 }
        guard !validDepths.isEmpty else { return 0 }
        return validDepths.reduce(0, +) / Float(validDepths.count)
    }

    /// Depth range (min, max)
    var depthRange: (min: Float, max: Float) {
        let validDepths = depthValues.filter { $0.isFinite && $0 > 0 }
        guard let minDepth = validDepths.min(),
              let maxDepth = validDepths.max() else {
            return (0, 0)
        }
        return (minDepth, maxDepth)
    }
}

// MARK: - Binary Serialization

extension DepthFrame {

    /// Serialize to binary data for network transfer
    func toBinaryData() -> Data {
        var data = Data()
        data.reserveCapacity(totalSize)

        // UUID (16 bytes)
        withUnsafeBytes(of: id.uuid) { data.append(contentsOf: $0) }

        // Timestamp (8 bytes)
        var ts = timestamp
        withUnsafeBytes(of: &ts) { data.append(contentsOf: $0) }

        // Camera transform (64 bytes - 16 floats)
        var transform = cameraTransform
        withUnsafeBytes(of: &transform) { data.append(contentsOf: $0) }

        // Camera intrinsics (36 bytes - 9 floats)
        var intrinsics = cameraIntrinsics
        withUnsafeBytes(of: &intrinsics) { data.append(contentsOf: $0) }

        // Dimensions (8 bytes)
        var w = UInt32(width)
        var h = UInt32(height)
        withUnsafeBytes(of: &w) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &h) { data.append(contentsOf: $0) }

        // Depth values
        depthValues.withUnsafeBytes { data.append(contentsOf: $0) }

        // Confidence values (if present)
        if let confidences = confidenceValues {
            confidences.withUnsafeBytes { data.append(contentsOf: $0) }
        }

        return data
    }

    /// Deserialize from binary data
    static func fromBinaryData(_ data: Data, hasConfidence: Bool) -> DepthFrame? {
        guard data.count >= 132 else { return nil } // Minimum header size

        var offset = 0

        // UUID
        let uuidBytes = data.subdata(in: offset..<offset+16)
        let uuid = uuidBytes.withUnsafeBytes { $0.load(as: uuid_t.self) }
        let id = UUID(uuid: uuid)
        offset += 16

        // Timestamp
        let timestamp = data.subdata(in: offset..<offset+8).withUnsafeBytes {
            $0.load(as: TimeInterval.self)
        }
        offset += 8

        // Transform
        let transform = data.subdata(in: offset..<offset+64).withUnsafeBytes {
            $0.load(as: simd_float4x4.self)
        }
        offset += 64

        // Intrinsics
        let intrinsics = data.subdata(in: offset..<offset+36).withUnsafeBytes {
            $0.load(as: simd_float3x3.self)
        }
        offset += 36

        // Dimensions
        let width = Int(data.subdata(in: offset..<offset+4).withUnsafeBytes {
            $0.load(as: UInt32.self)
        })
        offset += 4

        let height = Int(data.subdata(in: offset..<offset+4).withUnsafeBytes {
            $0.load(as: UInt32.self)
        })
        offset += 4

        let depthCount = width * height
        let depthSize = depthCount * MemoryLayout<Float>.size

        guard data.count >= offset + depthSize else { return nil }

        // Depth values
        let depthData = data.subdata(in: offset..<offset+depthSize)
        let depthValues = depthData.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        offset += depthSize

        // Confidence values
        var confidenceValues: [UInt8]? = nil
        if hasConfidence && data.count >= offset + depthCount {
            let confData = data.subdata(in: offset..<offset+depthCount)
            confidenceValues = Array(confData)
        }

        return DepthFrame(
            id: id,
            timestamp: timestamp,
            cameraTransform: transform,
            cameraIntrinsics: intrinsics,
            width: width,
            height: height,
            depthValues: depthValues,
            confidenceValues: confidenceValues
        )
    }
}

// MARK: - Depth Frame Buffer

/// Thread-safe buffer for collecting depth frames during scanning
actor DepthFrameBuffer {
    private var frames: [DepthFrame] = []
    private let maxFrames: Int
    private let captureInterval: Int // Capture every Nth frame

    private var frameCounter = 0

    init(maxFrames: Int = 500, captureInterval: Int = 3) {
        self.maxFrames = maxFrames
        self.captureInterval = captureInterval
    }

    /// Add frame if capture interval is met and buffer not full
    func addFrame(_ frame: DepthFrame) -> Bool {
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

    /// Get all captured frames
    func getAllFrames() -> [DepthFrame] {
        frames
    }

    /// Get frame count
    var count: Int {
        frames.count
    }

    /// Total size in bytes
    var totalSizeBytes: Int {
        frames.reduce(0) { $0 + $1.totalSize }
    }

    /// Clear buffer
    func clear() {
        frames.removeAll()
        frameCounter = 0
    }

    /// Get statistics
    func getStatistics() -> DepthBufferStatistics {
        DepthBufferStatistics(
            frameCount: frames.count,
            totalSizeBytes: totalSizeBytes,
            averageFrameSize: frames.isEmpty ? 0 : totalSizeBytes / frames.count,
            oldestTimestamp: frames.first?.timestamp,
            newestTimestamp: frames.last?.timestamp
        )
    }
}

struct DepthBufferStatistics: Sendable {
    let frameCount: Int
    let totalSizeBytes: Int
    let averageFrameSize: Int
    let oldestTimestamp: TimeInterval?
    let newestTimestamp: TimeInterval?

    var durationSeconds: TimeInterval? {
        guard let oldest = oldestTimestamp, let newest = newestTimestamp else {
            return nil
        }
        return newest - oldest
    }
}
