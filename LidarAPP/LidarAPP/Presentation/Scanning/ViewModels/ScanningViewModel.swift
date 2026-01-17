import SwiftUI
import RealityKit
import ARKit
import Combine

/// ViewModel for the scanning interface
@MainActor
@Observable
final class ScanningViewModel {

    // MARK: - Published State

    var isScanning: Bool = false
    var showMeshVisualization: Bool = true
    var showPreview: Bool = false
    var showError: Bool = false
    var errorMessage: String?

    // Statistics
    var pointCount: Int = 0
    var meshFaceCount: Int = 0
    var trackingStateText: String = "Initializing"
    var worldMappingStatusText: String = "Not Available"
    var scanQuality: ScanQuality = .poor

    var canStartScanning: Bool {
        arSessionManager.sessionState == .running &&
        arSessionManager.trackingState == .normal
    }

    // MARK: - Session

    let session: ScanSession

    // MARK: - Dependencies

    private let arSessionManager: ARSessionManager
    private let meshProcessor = MeshAnchorProcessor()
    private let pointCloudExtractor = PointCloudExtractor()

    private var scanStartTime: Date?

    // MARK: - Initialization

    init(session: ScanSession = ScanSession()) {
        self.session = session
        self.arSessionManager = ARSessionManager()
    }

    // MARK: - AR Session Setup

    func setupARSession(with arView: ARView) {
        arSessionManager.setup(with: arView)

        // Set up callbacks
        arSessionManager.onMeshUpdate = { [weak self] meshAnchor in
            Task { @MainActor in
                self?.handleMeshUpdate(meshAnchor)
            }
        }

        arSessionManager.onMeshRemoved = { [weak self] identifier in
            Task { @MainActor in
                self?.session.removeMesh(identifier: identifier)
                self?.updateStatistics()
            }
        }

        arSessionManager.onFrameUpdate = { [weak self] frame in
            Task { @MainActor in
                self?.handleFrameUpdate(frame)
            }
        }

        arSessionManager.onTrackingStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.updateTrackingState(state)
            }
        }

        // Start session
        arSessionManager.startSession()

        // Set initial visualization
        arSessionManager.setMeshVisualization(enabled: showMeshVisualization)
    }

    // MARK: - Scanning Control

    func startScanning() {
        guard canStartScanning else { return }

        isScanning = true
        scanStartTime = Date()
        session.startScanning()
    }

    func pauseScanning() {
        isScanning = false
        session.pauseScanning()
    }

    func resumeScanning() {
        guard session.state == .paused else { return }
        isScanning = true
        session.resumeScanning()
    }

    func stopScanning() {
        isScanning = false
        session.stopScanning()

        // Generate final point cloud from all mesh anchors
        let meshAnchors = arSessionManager.getAllMeshAnchors()
        session.pointCloud = pointCloudExtractor.extractPointCloud(from: meshAnchors)

        showPreview = true
    }

    func cancelScanning() {
        isScanning = false
        arSessionManager.stopSession()
    }

    // MARK: - Frame Handling

    private func handleFrameUpdate(_ frame: ARFrame) {
        // Update world mapping status
        updateWorldMappingStatus(frame.worldMappingStatus)

        guard isScanning else { return }

        // Record camera trajectory
        session.addCameraPosition(frame.camera.transform)

        // Update scan quality
        updateScanQuality(frame)
    }

    private func handleMeshUpdate(_ meshAnchor: ARMeshAnchor) {
        guard isScanning else { return }

        // Process mesh anchor
        let meshData = meshProcessor.extractMeshData(from: meshAnchor)
        session.addMesh(meshData)

        // Update statistics
        updateStatistics()
    }

    // MARK: - State Updates

    private func updateTrackingState(_ state: ARCamera.TrackingState) {
        trackingStateText = state.displayName
    }

    private func updateWorldMappingStatus(_ status: ARFrame.WorldMappingStatus) {
        worldMappingStatusText = status.displayName
    }

    private func updateScanQuality(_ frame: ARFrame) {
        let trackingGood = frame.camera.trackingState == .normal
        let mappingGood = frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending
        let hasDepth = frame.sceneDepth != nil

        if trackingGood && mappingGood && hasDepth {
            scanQuality = .excellent
        } else if trackingGood && hasDepth {
            scanQuality = .good
        } else if trackingGood {
            scanQuality = .fair
        } else {
            scanQuality = .poor
        }
    }

    private func updateStatistics() {
        meshFaceCount = session.faceCount
        pointCount = session.vertexCount
    }

    // MARK: - Visualization Toggle

    func toggleMeshVisualization() {
        showMeshVisualization.toggle()
        arSessionManager.setMeshVisualization(enabled: showMeshVisualization)
    }

    // MARK: - Error Handling

    func dismissError() {
        showError = false
        errorMessage = nil
    }
}

// MARK: - Scan Quality

enum ScanQuality: Int, CaseIterable {
    case poor = 1
    case fair = 2
    case good = 4
    case excellent = 5

    var level: Int { rawValue }

    var color: Color {
        switch self {
        case .poor: return .red
        case .fair: return .orange
        case .good: return .yellow
        case .excellent: return .green
        }
    }

    var displayName: String {
        switch self {
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }
}
