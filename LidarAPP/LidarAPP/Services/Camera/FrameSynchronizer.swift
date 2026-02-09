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

        var alignmentQuality: AlignmentQuality {
            let colorWidth = imageResolution.width
            let depthWidth = depthResolution.width
            let ratio = colorWidth / depthWidth

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
        var maxTimestampDelta: TimeInterval = 0.05
        var bufferSize: Int = 10
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

    /// Publisher for synchronized frames
    let synchronizedFramePublisher = PassthroughSubject<SynchronizedFrame, Never>()

    private var configuration: Configuration
    private var latencyAccumulator: Double = 0
    private var latencyCount: Int = 0

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        debugLog("FrameSynchronizer initialized", category: .logCategoryAR)
    }

    // MARK: - Frame Processing

    /// Process incoming AR frame and emit synchronized frame if depth is available
    func processFrame(_ frame: ARFrame) {
        guard isActive else { return }

        statistics.totalFrames += 1

        guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            statistics.droppedFrames += 1
            return
        }

        let latency = CACurrentMediaTime() - frame.timestamp
        latencyAccumulator += latency
        latencyCount += 1
        statistics.averageLatency = latencyAccumulator / Double(latencyCount)

        let camera = frame.camera
        let depthWidth = CVPixelBufferGetWidth(sceneDepth.depthMap)
        let depthHeight = CVPixelBufferGetHeight(sceneDepth.depthMap)

        let syncFrame = SynchronizedFrame(
            timestamp: frame.timestamp,
            colorImage: frame.capturedImage,
            depthMap: sceneDepth.depthMap,
            confidenceMap: sceneDepth.confidenceMap,
            cameraTransform: camera.transform,
            cameraIntrinsics: camera.intrinsics,
            imageResolution: camera.imageResolution,
            depthResolution: CGSize(width: depthWidth, height: depthHeight),
            trackingState: camera.trackingState
        )

        statistics.synchronizedFrames += 1
        statistics.lastSyncTimestamp = frame.timestamp

        synchronizedFramePublisher.send(syncFrame)
    }

    // MARK: - Control

    func start() {
        isActive = true
        resetStatistics()
        debugLog("FrameSynchronizer started", category: .logCategoryAR)
    }

    func stop() {
        isActive = false
        debugLog("FrameSynchronizer stopped", category: .logCategoryAR)
    }

    func resetStatistics() {
        statistics = SyncStatistics()
        latencyAccumulator = 0
        latencyCount = 0
    }

    // MARK: - Depth-Color Alignment Utilities

    /// Project depth value to color image coordinates
    static func projectDepthToColor(
        depthPoint: CGPoint,
        depthResolution: CGSize,
        colorResolution: CGSize,
        cameraIntrinsics: simd_float3x3
    ) -> CGPoint {
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

    /// Generate UV coordinates for a 3D point
    static func generateUV(
        for worldPoint: simd_float3,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        imageResolution: CGSize
    ) -> simd_float2? {
        let cameraInverse = cameraTransform.inverse
        let cameraPoint = cameraInverse * simd_float4(worldPoint, 1)

        guard cameraPoint.z > 0 else { return nil }

        let fx = cameraIntrinsics[0, 0]
        let fy = cameraIntrinsics[1, 1]
        let cx = cameraIntrinsics[2, 0]
        let cy = cameraIntrinsics[2, 1]

        let imageX = (cameraPoint.x / cameraPoint.z) * fx + cx
        let imageY = (cameraPoint.y / cameraPoint.z) * fy + cy

        let u = imageX / Float(imageResolution.width)
        let v = imageY / Float(imageResolution.height)

        guard u >= 0 && u <= 1 && v >= 0 && v <= 1 else { return nil }

        return simd_float2(u, v)
    }
}
