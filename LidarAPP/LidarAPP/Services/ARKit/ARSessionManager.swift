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

    /// The scan mode for configuring world alignment (exterior uses GPS/heading)
    var scanMode: ScanMode = .exterior

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

        // World alignment based on scan mode
        // Exterior mode uses gravityAndHeading for GPS/compass integration
        // This allows accurate real-world positioning for outdoor scans
        switch scanMode {
        case .exterior:
            // Use gravity + compass for exterior scans (buildings, facades)
            // This provides true-north orientation for outdoor environments
            arConfig.worldAlignment = .gravityAndHeading
        case .interior, .object:
            // Use gravity-only for interior scans
            arConfig.worldAlignment = .gravity
        }

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
            // Check if the error is related to heading/location
            // If so, retry with gravity-only alignment
            if let arError = error as? ARError {
                switch arError.code {
                case .sensorUnavailable, .sensorFailed, .worldTrackingFailed:
                    // If using gravityAndHeading and it failed, fall back to gravity only
                    if self.scanMode == .exterior {
                        print("ARSession: gravityAndHeading failed, falling back to gravity-only")
                        self.scanMode = .interior // Use gravity-only
                        self.configuration = self.createConfiguration()
                        if let config = self.configuration {
                            self.arView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                            self.sessionState = .running
                            return
                        }
                    }
                default:
                    break
                }
            }

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

// MARK: - ARWorldMap Persistence

extension ARSessionManager {

    /// Check if current world map is good for saving
    var canSaveWorldMap: Bool {
        worldMappingStatus == .mapped || worldMappingStatus == .extending
    }

    /// Request current world map for saving
    func getCurrentWorldMap() async throws -> ARWorldMap {
        guard let arView = arView else {
            throw ARSessionError.notConfigured
        }

        return try await withCheckedThrowingContinuation { continuation in
            arView.session.getCurrentWorldMap { worldMap, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let worldMap = worldMap {
                    continuation.resume(returning: worldMap)
                } else {
                    continuation.resume(throwing: ARWorldMapError.unavailable)
                }
            }
        }
    }

    /// Resume session with a saved world map
    func resumeWithWorldMap(_ worldMap: ARWorldMap) {
        guard var config = configuration else { return }

        config.initialWorldMap = worldMap
        arView?.session.run(config, options: [.resetTracking])
        sessionState = .running
    }

    /// Resume session with world map and reset anchors
    func resumeWithWorldMap(_ worldMap: ARWorldMap, removeExistingAnchors: Bool) {
        guard var config = configuration else { return }

        config.initialWorldMap = worldMap

        var options: ARSession.RunOptions = [.resetTracking]
        if removeExistingAnchors {
            options.insert(.removeExistingAnchors)
        }

        arView?.session.run(config, options: options)
        sessionState = .running
        meshAnchors.removeAll()
    }

    /// Get world mapping status text for UI
    var worldMappingStatusText: String {
        switch worldMappingStatus {
        case .notAvailable:
            return "Move around to map the environment"
        case .limited:
            return "Continue scanning to improve map"
        case .extending:
            return "Map is extending - good for saving"
        case .mapped:
            return "Map is ready - can save for later"
        @unknown default:
            return "Unknown mapping status"
        }
    }

    /// Get tracking state text for UI
    var trackingStateText: String {
        switch trackingState {
        case .notAvailable:
            return "Tracking not available"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "Initializing - please wait"
            case .excessiveMotion:
                return "Slow down - moving too fast"
            case .insufficientFeatures:
                return "Point at more detailed areas"
            case .relocalizing:
                return "Relocalizing to saved map..."
            @unknown default:
                return "Limited tracking"
            }
        case .normal:
            return "Tracking OK"
        }
    }
}

// MARK: - ARWorldMap Errors

enum ARWorldMapError: LocalizedError {
    case unavailable
    case saveFailed
    case loadFailed
    case relocalizationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "World map is not available. Continue scanning to build the map."
        case .saveFailed:
            return "Failed to save world map."
        case .loadFailed:
            return "Failed to load saved world map."
        case .relocalizationFailed:
            return "Could not relocalize to the saved environment. The scene may have changed."
        }
    }
}
