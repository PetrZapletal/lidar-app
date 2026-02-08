import Foundation
import simd
import Combine
import QuartzCore

/// Mock AR session manager for simulator testing
@MainActor
@Observable
final class MockARSessionManager {

    // MARK: - State

    enum SessionState {
        case notStarted
        case running
        case paused
        case stopped
    }

    // MARK: - Properties

    private(set) var state: SessionState = .notStarted
    private(set) var currentFrame: MockARFrame?
    private(set) var meshAnchors: [UUID: MeshData] = [:]

    var isRunning: Bool { state == .running }

    // Simulation
    private var simulationTimer: Timer?
    private var frameCount: Int = 0
    private var scanProgress: Float = 0

    // Callbacks
    var onFrameUpdate: ((MockARFrame) -> Void)?
    var onMeshUpdate: ((MeshData) -> Void)?
    var onTrackingStateChanged: ((String) -> Void)?

    // MARK: - Mock AR Frame

    struct MockARFrame {
        let timestamp: TimeInterval
        let cameraTransform: simd_float4x4
        let pointCloud: PointCloud?
        let lightEstimate: Float
    }

    // MARK: - Session Control

    func startSession() {
        guard state != .running else { return }

        state = .running
        frameCount = 0
        scanProgress = 0

        onTrackingStateChanged?("Normal")

        // Start simulation
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.simulateFrame()
            }
        }
    }

    func pauseSession() {
        guard state == .running else { return }
        state = .paused
        simulationTimer?.invalidate()
    }

    func resumeSession() {
        guard state == .paused else { return }
        startSession()
    }

    func stopSession() {
        state = .stopped
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    // MARK: - Simulation

    private func simulateFrame() {
        frameCount += 1

        // Simulate camera movement
        let time = Float(frameCount) / 30.0
        let cameraPosition = simd_float3(
            sin(time * 0.5) * 2,
            1.5,
            cos(time * 0.5) * 2
        )

        let cameraTransform = simd_float4x4(translation: cameraPosition)

        // Generate mock point cloud periodically
        var pointCloud: PointCloud? = nil
        if frameCount % 10 == 0 {
            pointCloud = generateIncrementalPointCloud()
        }

        // Create mock frame
        let frame = MockARFrame(
            timestamp: CACurrentMediaTime(),
            cameraTransform: cameraTransform,
            pointCloud: pointCloud,
            lightEstimate: 1000.0 + Float.random(in: -100...100)
        )

        currentFrame = frame
        onFrameUpdate?(frame)

        // Update scan progress
        scanProgress = min(scanProgress + 0.002, 1.0)

        // Generate mesh updates periodically
        if frameCount % 30 == 0 {
            generateMeshUpdate()
        }
    }

    private func generateIncrementalPointCloud() -> PointCloud {
        let angle = Float(frameCount) / 30.0 * 0.5
        let centerX = sin(angle) * 2
        let centerZ = cos(angle) * 2

        var points: [simd_float3] = []
        var colors: [simd_float4] = []

        // Generate points in view frustum
        for _ in 0..<100 {
            let x = centerX + Float.random(in: -1...1)
            let y = Float.random(in: 0...2.5)
            let z = centerZ + Float.random(in: -1...1)

            points.append(simd_float3(x, y, z))

            // Color based on height
            let normalizedY = y / 2.5
            colors.append(simd_float4(normalizedY, 0.5, 1 - normalizedY, 1))
        }

        return PointCloud(points: points, colors: colors, confidences: nil)
    }

    private func generateMeshUpdate() {
        let meshId = UUID()

        // Generate a small mesh patch
        let offset = simd_float3(
            Float.random(in: -2...2),
            0,
            Float.random(in: -2...2)
        )

        var vertices: [simd_float3] = []
        var normals: [simd_float3] = []
        var faces: [simd_uint3] = []

        // Create a small grid
        let gridSize = 3
        let step: Float = 0.2

        for z in 0...gridSize {
            for x in 0...gridSize {
                let pos = offset + simd_float3(Float(x) * step, 0, Float(z) * step)
                vertices.append(pos)
                normals.append(simd_float3(0, 1, 0))
            }
        }

        for z in 0..<gridSize {
            for x in 0..<gridSize {
                let tl = UInt32(z * (gridSize + 1) + x)
                let tr = tl + 1
                let bl = tl + UInt32(gridSize + 1)
                let br = bl + 1

                faces.append(simd_uint3(tl, bl, tr))
                faces.append(simd_uint3(tr, bl, br))
            }
        }

        let mesh = MeshData(
            anchorIdentifier: meshId,
            vertices: vertices,
            normals: normals,
            faces: faces
        )

        meshAnchors[meshId] = mesh
        onMeshUpdate?(mesh)
    }

    // MARK: - Data Access

    func getCombinedPointCloud() -> PointCloud? {
        MockDataProvider.shared.generateRoomPointCloud()
    }

    func getAllMeshes() -> [MeshData] {
        Array(meshAnchors.values)
    }

    var currentScanProgress: Float {
        scanProgress
    }
}

// MARK: - Matrix Extension

private extension simd_float4x4 {
    init(translation: simd_float3) {
        self.init(columns: (
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(translation.x, translation.y, translation.z, 1)
        ))
    }
}
