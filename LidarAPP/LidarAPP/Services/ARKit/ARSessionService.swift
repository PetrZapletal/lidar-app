import ARKit
import RealityKit
import Combine

/// Production ARKit session service managing LiDAR scanning lifecycle
@MainActor
@Observable
final class ARSessionService: NSObject, ARSessionServiceProtocol {

    // MARK: - Protocol Properties

    private(set) var isScanning: Bool = false
    private(set) var trackingState: ARCamera.TrackingState? = nil
    private(set) var meshAnchorCount: Int = 0
    private(set) var totalVertexCount: Int = 0
    private(set) var totalFaceCount: Int = 0

    var meshAnchorsPublisher: AnyPublisher<[ARMeshAnchor], Never> {
        meshAnchorsSubject.eraseToAnyPublisher()
    }

    // MARK: - Internal State

    private let session = ARSession()
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var currentMode: ScanMode?
    private let meshAnchorsSubject = PassthroughSubject<[ARMeshAnchor], Never>()

    // MARK: - Initialization

    override init() {
        super.init()
        session.delegate = self
        debugLog("ARSessionService initialized", category: .logCategoryAR)
    }

    // MARK: - Protocol Methods

    func startSession(mode: ScanMode) throws {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            errorLog("LiDAR not available on this device", category: .logCategoryAR)
            throw ScanError.lidarNotAvailable
        }

        currentMode = mode
        let configuration = createConfiguration(for: mode)

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        meshAnchors.removeAll()
        meshAnchorCount = 0
        totalVertexCount = 0
        totalFaceCount = 0
        isScanning = true

        debugLog("AR session started with mode: \(mode.rawValue)", category: .logCategoryAR)
    }

    func pauseSession() {
        session.pause()
        isScanning = false
        debugLog("AR session paused", category: .logCategoryAR)
    }

    func resumeSession() {
        guard let mode = currentMode else {
            warningLog("Cannot resume - no mode set", category: .logCategoryAR)
            return
        }

        let configuration = createConfiguration(for: mode)
        session.run(configuration)
        isScanning = true
        debugLog("AR session resumed", category: .logCategoryAR)
    }

    func stopSession() {
        session.pause()
        isScanning = false
        currentMode = nil
        debugLog("AR session stopped", category: .logCategoryAR)
    }

    func getMeshAnchors() -> [ARMeshAnchor] {
        Array(meshAnchors.values)
    }

    func getCurrentFrame() -> ARFrame? {
        session.currentFrame
    }

    // MARK: - Scene Phase Handling

    func handleScenePhaseChange(isActive: Bool) {
        if isActive {
            if currentMode != nil && !isScanning {
                resumeSession()
            }
        } else {
            if isScanning {
                pauseSession()
            }
        }
    }

    // MARK: - Configuration

    private func createConfiguration(for mode: ScanMode) -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()

        // Mesh reconstruction with classification
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        // Scene depth
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
            config.frameSemantics.insert(.smoothedSceneDepth)
        }

        config.environmentTexturing = .automatic
        config.planeDetection = [.horizontal, .vertical]

        // High resolution capture if available
        if let hiResFormat = ARWorldTrackingConfiguration.recommendedVideoFormatFor4KResolution {
            config.videoFormat = hiResFormat
        }

        // World alignment based on scan mode
        switch mode {
        case .exterior:
            config.worldAlignment = .gravityAndHeading
        case .interior, .object:
            config.worldAlignment = .gravity
        }

        return config
    }

    // MARK: - Mesh Statistics

    private func updateMeshStatistics() {
        meshAnchorCount = meshAnchors.count
        var vertices = 0
        var faces = 0
        for anchor in meshAnchors.values {
            vertices += anchor.geometry.vertices.count
            faces += anchor.geometry.faces.count
        }
        totalVertexCount = vertices
        totalFaceCount = faces
    }
}

// MARK: - ARSessionDelegate

extension ARSessionService: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.trackingState = frame.camera.trackingState
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            var updated = false
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    self.meshAnchors[meshAnchor.identifier] = meshAnchor
                    updated = true
                }
            }
            if updated {
                self.updateMeshStatistics()
                self.meshAnchorsSubject.send(Array(self.meshAnchors.values))
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            var updated = false
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    self.meshAnchors[meshAnchor.identifier] = meshAnchor
                    updated = true
                }
            }
            if updated {
                self.updateMeshStatistics()
                self.meshAnchorsSubject.send(Array(self.meshAnchors.values))
            }
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            var updated = false
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    self.meshAnchors.removeValue(forKey: meshAnchor.identifier)
                    updated = true
                }
            }
            if updated {
                self.updateMeshStatistics()
                self.meshAnchorsSubject.send(Array(self.meshAnchors.values))
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            // If exterior mode with gravityAndHeading failed, fall back to gravity-only
            if let arError = error as? ARError, self.currentMode == .exterior {
                switch arError.code {
                case .sensorUnavailable, .sensorFailed, .worldTrackingFailed:
                    warningLog(
                        "gravityAndHeading failed, falling back to gravity-only: \(arError.localizedDescription)",
                        category: .logCategoryAR
                    )
                    self.currentMode = .interior
                    let fallbackConfig = self.createConfiguration(for: .interior)
                    session.run(fallbackConfig, options: [.resetTracking, .removeExistingAnchors])
                    return
                default:
                    break
                }
            }

            errorLog("AR session failed: \(error.localizedDescription)", category: .logCategoryAR)
            self.isScanning = false
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            warningLog("AR session interrupted", category: .logCategoryAR)
            self.isScanning = false
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            debugLog("AR session interruption ended", category: .logCategoryAR)
            self.resumeSession()
        }
    }
}
