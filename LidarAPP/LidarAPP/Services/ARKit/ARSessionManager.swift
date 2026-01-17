import ARKit
import RealityKit
import Combine

/// Manages ARKit session lifecycle and LiDAR configuration
@MainActor
@Observable
final class ARSessionManager: NSObject {

    // MARK: - Published State

    private(set) var sessionState: ARSessionState = .notStarted
    private(set) var trackingState: ARCamera.TrackingState = .notAvailable
    private(set) var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    private(set) var meshAnchors: [UUID: ARMeshAnchor] = [:]

    // MARK: - Callbacks

    var onMeshUpdate: ((ARMeshAnchor) -> Void)?
    var onMeshRemoved: ((UUID) -> Void)?
    var onFrameUpdate: ((ARFrame) -> Void)?
    var onTrackingStateChanged: ((ARCamera.TrackingState) -> Void)?

    // MARK: - Properties

    private(set) var arView: ARView?
    private var configuration: ARWorldTrackingConfiguration?

    // MARK: - Configuration

    struct Configuration {
        var enableMeshClassification: Bool = true
        var enableHighResCapture: Bool = true
        var enableSmoothedDepth: Bool = true
        var planeDetection: ARWorldTrackingConfiguration.PlaneDetection = [.horizontal, .vertical]
    }

    private var config: Configuration

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.config = configuration
        super.init()
    }

    // MARK: - Setup

    func setup(with arView: ARView) {
        self.arView = arView
        arView.session.delegate = self

        // Configure AR view for scanning
        arView.automaticallyConfigureSession = false
        arView.renderOptions = [
            .disableMotionBlur,
            .disableDepthOfField,
            .disablePersonOcclusion
        ]

        // Enable scene understanding visualization
        arView.environment.sceneUnderstanding.options = [
            .occlusion,
            .receivesLighting
        ]

        // Create AR configuration
        configuration = createConfiguration()
    }

    private func createConfiguration() -> ARWorldTrackingConfiguration {
        let arConfig = ARWorldTrackingConfiguration()

        // Enable scene reconstruction for LiDAR mesh
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            if config.enableMeshClassification {
                arConfig.sceneReconstruction = .meshWithClassification
            } else {
                arConfig.sceneReconstruction = .mesh
            }
        }

        // Enable frame semantics for depth
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            arConfig.frameSemantics.insert(.sceneDepth)
            if config.enableSmoothedDepth {
                arConfig.frameSemantics.insert(.smoothedSceneDepth)
            }
        }

        // Environment texturing for better textures
        arConfig.environmentTexturing = .automatic

        // Plane detection
        arConfig.planeDetection = config.planeDetection

        // High resolution frame capture
        if config.enableHighResCapture,
           let hiResFormat = ARWorldTrackingConfiguration.recommendedVideoFormatFor4KResolution {
            arConfig.videoFormat = hiResFormat
        }

        // World alignment
        arConfig.worldAlignment = .gravity

        return arConfig
    }

    // MARK: - Session Control

    func startSession() {
        guard let arView = arView, let configuration = configuration else {
            sessionState = .failed(.notConfigured)
            return
        }

        guard DeviceCapabilities.hasLiDAR else {
            sessionState = .failed(.lidarNotAvailable)
            return
        }

        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        sessionState = .running
        meshAnchors.removeAll()
    }

    func pauseSession() {
        arView?.session.pause()
        sessionState = .paused
    }

    func resumeSession() {
        guard let configuration = configuration else { return }
        arView?.session.run(configuration)
        sessionState = .running
    }

    func stopSession() {
        arView?.session.pause()
        sessionState = .stopped
    }

    // MARK: - Mesh Access

    func getAllMeshAnchors() -> [ARMeshAnchor] {
        Array(meshAnchors.values)
    }

    func getMeshAnchor(identifier: UUID) -> ARMeshAnchor? {
        meshAnchors[identifier]
    }

    // MARK: - Debug Visualization

    func setMeshVisualization(enabled: Bool) {
        if enabled {
            arView?.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView?.debugOptions.remove(.showSceneUnderstanding)
        }
    }

    func setWorldOriginVisualization(enabled: Bool) {
        if enabled {
            arView?.debugOptions.insert(.showWorldOrigin)
        } else {
            arView?.debugOptions.remove(.showWorldOrigin)
        }
    }

    func setFeaturePointsVisualization(enabled: Bool) {
        if enabled {
            arView?.debugOptions.insert(.showFeaturePoints)
        } else {
            arView?.debugOptions.remove(.showFeaturePoints)
        }
    }

    // MARK: - High Resolution Capture

    func captureHighResolutionFrame() async -> ARFrame? {
        guard let arView = arView else { return nil }

        return await withCheckedContinuation { continuation in
            arView.session.captureHighResolutionFrame { frame, error in
                if let error = error {
                    print("High-res capture error: \(error)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: frame)
                }
            }
        }
    }

    // MARK: - Current Frame Access

    var currentFrame: ARFrame? {
        arView?.session.currentFrame
    }
}

// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.trackingState = frame.camera.trackingState
            self.worldMappingStatus = frame.worldMappingStatus
            self.onFrameUpdate?(frame)
            self.onTrackingStateChanged?(frame.camera.trackingState)
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    self.meshAnchors[meshAnchor.identifier] = meshAnchor
                    self.onMeshUpdate?(meshAnchor)
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    self.meshAnchors[meshAnchor.identifier] = meshAnchor
                    self.onMeshUpdate?(meshAnchor)
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    self.meshAnchors.removeValue(forKey: meshAnchor.identifier)
                    self.onMeshRemoved?(meshAnchor.identifier)
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.sessionState = .failed(.sessionError(error))
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.sessionState = .interrupted
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.resumeSession()
        }
    }
}

// MARK: - Supporting Types

enum ARSessionState: Equatable {
    case notStarted
    case running
    case paused
    case stopped
    case interrupted
    case failed(ARSessionError)

    var isActive: Bool {
        self == .running
    }

    var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .running: return "Running"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        case .interrupted: return "Interrupted"
        case .failed: return "Failed"
        }
    }
}

enum ARSessionError: Error, Equatable {
    case notConfigured
    case lidarNotAvailable
    case cameraPermissionDenied
    case sessionError(Error)

    static func == (lhs: ARSessionError, rhs: ARSessionError) -> Bool {
        switch (lhs, rhs) {
        case (.notConfigured, .notConfigured),
             (.lidarNotAvailable, .lidarNotAvailable),
             (.cameraPermissionDenied, .cameraPermissionDenied):
            return true
        case (.sessionError, .sessionError):
            return true
        default:
            return false
        }
    }

    var localizedDescription: String {
        switch self {
        case .notConfigured:
            return "AR session is not configured."
        case .lidarNotAvailable:
            return "This device does not have a LiDAR sensor."
        case .cameraPermissionDenied:
            return "Camera access is required for scanning."
        case .sessionError(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - Tracking State Extensions

extension ARCamera.TrackingState {
    var displayName: String {
        switch self {
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            return "Limited: \(reason.displayName)"
        case .normal:
            return "Normal"
        }
    }

    var isGood: Bool {
        self == .normal
    }
}

extension ARCamera.TrackingState.Reason {
    var displayName: String {
        switch self {
        case .initializing:
            return "Initializing"
        case .excessiveMotion:
            return "Too Fast"
        case .insufficientFeatures:
            return "Low Features"
        case .relocalizing:
            return "Relocalizing"
        @unknown default:
            return "Unknown"
        }
    }
}

extension ARFrame.WorldMappingStatus {
    var displayName: String {
        switch self {
        case .notAvailable:
            return "Not Available"
        case .limited:
            return "Limited"
        case .extending:
            return "Extending"
        case .mapped:
            return "Mapped"
        @unknown default:
            return "Unknown"
        }
    }

    var isGood: Bool {
        self == .mapped || self == .extending
    }
}
