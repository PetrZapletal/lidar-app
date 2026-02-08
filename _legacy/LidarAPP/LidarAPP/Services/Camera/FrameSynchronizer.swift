import ARKit
import simd
import Combine

/// Synchronizes LiDAR depth data with camera RGB frames
@MainActor
@Observable
final class FrameSynchronizer {

    // MARK: - Synchronized Frame

    struct SynchronizedFrame: Sendable {
        let timestamp: TimeInterval
        let colorImage: CVPixelBuffer
        let depthMap: CVPixelBuffer
        let confidenceMap: CVPixelBuffer?
        let cameraTransform: simd_float4x4
        let cameraIntrinsics: simd_float3x3
        let imageResolution: CGSize
        let depthResolution: CGSize
        let trackingState: ARCamera.TrackingState

        /// Alignment quality between color and depth
        var alignmentQuality: AlignmentQuality {
            // Check resolution ratio
            let colorWidth = imageResolution.width
            let depthWidth = depthResolution.width
            let ratio = colorWidth / depthWidth

            // Typical ratios: 4K/256 ≈ 15, 1920/256 ≈ 7.5
            if ratio < 10 {
                return .excellent
            } else if ratio < 20 {
                return .good
            } else {
                return .fair
            }
        }

        enum AlignmentQuality: String, Sendable {
            case excellent = "Excellent"
            case good = "Good"
            case fair = "Fair"
            case poor = "Poor"
        }
    }

    // MARK: - Configuration

    struct Configuration {
        var maxTimestampDelta: TimeInterval = 0.05  // 50ms max difference
        var bufferSize: Int = 10
        var autoAlign: Bool = true
        var interpolateDepth: Bool = false
    }

    // MARK: - Statistics

    struct SyncStatistics {
        var totalFrames: Int = 0
        var synchronizedFrames: Int = 0
        var droppedFrames: Int = 0
        var averageLatency: TimeInterval = 0
        var lastSyncTimestamp: TimeInterval = 0

        var synchronizationRate: Double {
            guard totalFrames > 0 else { return 0 }
            return Double(synchronizedFrames) / Double(totalFrames)
        }
    }

    // MARK: - Properties

    private(set) var statistics = SyncStatistics()
    private(set) var isActive: Bool = false

    private var configuration: Configuration
    private var colorFrameBuffer: RingBuffer<ARFrame>
    private var depthFrameBuffer: RingBuffer<(depth: CVPixelBuffer, confidence: CVPixelBuffer?, timestamp: TimeInterval)>

    private var latencyAccumulator: Double = 0
    private var latencyCount: Int = 0

    // Callbacks
    var onSynchronizedFrame: ((SynchronizedFrame) -> Void)?

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.colorFrameBuffer = RingBuffer(capacity: configuration.bufferSize)
        self.depthFrameBuffer = RingBuffer(capacity: configuration.bufferSize)
    }

    // MARK: - Frame Processing

    /// Process incoming AR frame
    func processFrame(_ frame: ARFrame) {
        guard isActive else { return }

        statistics.totalFrames += 1

        // Add to color buffer
        colorFrameBuffer.append(frame)

        // Check for depth data
        if let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth {
            depthFrameBuffer.append((
                depth: sceneDepth.depthMap,
                confidence: sceneDepth.confidenceMap,
                timestamp: frame.timestamp
            ))

            // Try to create synchronized frame
            if let syncFrame = createSynchronizedFrame(from: frame, depth: sceneDepth) {
                statistics.synchronizedFrames += 1
                statistics.lastSyncTimestamp = frame.timestamp

                onSynchronizedFrame?(syncFrame)
            }
        } else {
            statistics.droppedFrames += 1
        }
    }

    /// Create synchronized frame from AR frame with depth
    private func createSynchronizedFrame(
        from frame: ARFrame,
        depth: ARDepthData
    ) -> SynchronizedFrame? {
        let camera = frame.camera

        // Calculate latency
        let latency = CACurrentMediaTime() - frame.timestamp
        latencyAccumulator += latency
        latencyCount += 1
        statistics.averageLatency = latencyAccumulator / Double(latencyCount)

        let depthWidth = CVPixelBufferGetWidth(depth.depthMap)
        let depthHeight = CVPixelBufferGetHeight(depth.depthMap)

        return SynchronizedFrame(
            timestamp: frame.timestamp,
            colorImage: frame.capturedImage,
            depthMap: depth.depthMap,
            confidenceMap: depth.confidenceMap,
            cameraTransform: camera.transform,
            cameraIntrinsics: camera.intrinsics,
            imageResolution: camera.imageResolution,
            depthResolution: CGSize(width: depthWidth, height: depthHeight),
            trackingState: camera.trackingState
        )
    }

    /// Find best matching depth for a color frame timestamp
    private func findMatchingDepth(
        for timestamp: TimeInterval
    ) -> (depth: CVPixelBuffer, confidence: CVPixelBuffer?, timestamp: TimeInterval)? {
        var bestMatch: (depth: CVPixelBuffer, confidence: CVPixelBuffer?, timestamp: TimeInterval)?
        var bestDelta: TimeInterval = .greatestFiniteMagnitude

        for item in depthFrameBuffer.allItems() {
            let delta = abs(item.timestamp - timestamp)
            if delta < bestDelta && delta < configuration.maxTimestampDelta {
                bestDelta = delta
                bestMatch = item
            }
        }

        return bestMatch
    }

    // MARK: - Control

    func start() {
        isActive = true
        resetStatistics()
    }

    func stop() {
        isActive = false
    }

    func resetStatistics() {
        statistics = SyncStatistics()
        latencyAccumulator = 0
        latencyCount = 0
    }

    func clearBuffers() {
        colorFrameBuffer.clear()
        depthFrameBuffer.clear()
    }
}

// MARK: - Depth-Color Alignment

extension FrameSynchronizer {

    /// Project depth value to color image coordinates
    static func projectDepthToColor(
        depthPoint: CGPoint,
        depthResolution: CGSize,
        colorResolution: CGSize,
        cameraIntrinsics: simd_float3x3
    ) -> CGPoint {
        // Simple scaling - depth and color are aligned in ARKit
        let scaleX = colorResolution.width / depthResolution.width
        let scaleY = colorResolution.height / depthResolution.height

        return CGPoint(
            x: depthPoint.x * scaleX,
            y: depthPoint.y * scaleY
        )
    }

    /// Sample depth at color image coordinates
    static func sampleDepth(
        at colorPoint: CGPoint,
        depthMap: CVPixelBuffer,
        colorResolution: CGSize
    ) -> Float? {
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        // Convert color coordinates to depth coordinates
        let depthX = Int(colorPoint.x * CGFloat(depthWidth) / colorResolution.width)
        let depthY = Int(colorPoint.y * CGFloat(depthHeight) / colorResolution.height)

        guard depthX >= 0 && depthX < depthWidth &&
              depthY >= 0 && depthY < depthHeight else {
            return nil
        }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let depthData = baseAddress.assumingMemoryBound(to: Float32.self)
        let index = depthY * (bytesPerRow / MemoryLayout<Float32>.stride) + depthX

        return depthData[index]
    }

    /// Sample confidence at color image coordinates
    static func sampleConfidence(
        at colorPoint: CGPoint,
        confidenceMap: CVPixelBuffer,
        colorResolution: CGSize
    ) -> ARConfidenceLevel? {
        let confWidth = CVPixelBufferGetWidth(confidenceMap)
        let confHeight = CVPixelBufferGetHeight(confidenceMap)

        let confX = Int(colorPoint.x * CGFloat(confWidth) / colorResolution.width)
        let confY = Int(colorPoint.y * CGFloat(confHeight) / colorResolution.height)

        guard confX >= 0 && confX < confWidth &&
              confY >= 0 && confY < confHeight else {
            return nil
        }

        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            return nil
        }

        let confData = baseAddress.assumingMemoryBound(to: UInt8.self)
        let index = confY * bytesPerRow + confX
        let rawValue = Int(confData[index])

        return ARConfidenceLevel(rawValue: rawValue)
    }
}

// MARK: - Texture Mapping Helpers

extension FrameSynchronizer {

    /// Generate UV coordinates for a 3D point
    static func generateUV(
        for worldPoint: simd_float3,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        imageResolution: CGSize
    ) -> simd_float2? {
        // Transform world point to camera space
        let cameraInverse = cameraTransform.inverse
        let cameraPoint = cameraInverse * simd_float4(worldPoint, 1)

        // Check if point is behind camera
        guard cameraPoint.z > 0 else { return nil }

        // Project to image coordinates
        let fx = cameraIntrinsics[0, 0]
        let fy = cameraIntrinsics[1, 1]
        let cx = cameraIntrinsics[2, 0]
        let cy = cameraIntrinsics[2, 1]

        let imageX = (cameraPoint.x / cameraPoint.z) * fx + cx
        let imageY = (cameraPoint.y / cameraPoint.z) * fy + cy

        // Normalize to UV [0, 1]
        let u = imageX / Float(imageResolution.width)
        let v = imageY / Float(imageResolution.height)

        // Check bounds
        guard u >= 0 && u <= 1 && v >= 0 && v <= 1 else { return nil }

        return simd_float2(u, v)
    }

    /// Find best frame for texturing a mesh face
    static func findBestTextureFrame(
        for faceCenter: simd_float3,
        faceNormal: simd_float3,
        frames: [SynchronizedFrame]
    ) -> (frame: SynchronizedFrame, uv: simd_float2)? {
        var bestFrame: SynchronizedFrame?
        var bestUV: simd_float2?
        var bestScore: Float = -1

        for frame in frames {
            // Check if face is visible from this camera position
            let cameraPosition = simd_float3(
                frame.cameraTransform.columns.3.x,
                frame.cameraTransform.columns.3.y,
                frame.cameraTransform.columns.3.z
            )

            let viewDirection = simd_normalize(faceCenter - cameraPosition)
            let dotProduct = simd_dot(viewDirection, faceNormal)

            // Face should be roughly facing the camera
            guard dotProduct < -0.1 else { continue }

            // Generate UV
            guard let uv = generateUV(
                for: faceCenter,
                cameraTransform: frame.cameraTransform,
                cameraIntrinsics: frame.cameraIntrinsics,
                imageResolution: frame.imageResolution
            ) else { continue }

            // Score based on angle and UV position (prefer center of image)
            let angleScore = abs(dotProduct)
            let centerScore = 1 - max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2
            let score = angleScore * 0.7 + centerScore * 0.3

            if score > bestScore {
                bestScore = score
                bestFrame = frame
                bestUV = uv
            }
        }

        if let frame = bestFrame, let uv = bestUV {
            return (frame, uv)
        }
        return nil
    }
}

// MARK: - Ring Buffer

private class RingBuffer<T> {
    private var buffer: [T?]
    private var writeIndex: Int = 0
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    func append(_ item: T) {
        buffer[writeIndex] = item
        writeIndex = (writeIndex + 1) % capacity
    }

    func allItems() -> [T] {
        buffer.compactMap { $0 }
    }

    func clear() {
        buffer = Array(repeating: nil, count: capacity)
        writeIndex = 0
    }
}
