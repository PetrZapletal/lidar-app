import SwiftUI
import RealityKit
import ARKit
import Combine
import simd
import CoreImage
import UIKit

/// ViewModel for the scanning interface
@MainActor
@Observable
final class ScanningViewModel {

    // MARK: - Published State

    var isScanning: Bool = false
    var showMeshVisualization: Bool = false  // Disabled by default - "phantom geometry" fix
    var showPreview: Bool = false
    var showProcessing: Bool = false
    var showError: Bool = false
    var errorMessage: String?

    // Resume session UI
    var showResumeSheet: Bool = false
    var resumableSessions: [ScanSessionPersistence.PersistedSession] = []

    // Coverage overlay
    var showCoverageOverlay: Bool = true
    var currentCameraTransform: simd_float4x4 = matrix_identity_float4x4

    // Memory monitoring
    var memoryPressure: MemoryPressureLevel = .normal

    // ML model status
    var activeMLModels: [String] = []
    var isMLProcessing: Bool = false

    // Statistics
    var pointCount: Int = 0
    var meshFaceCount: Int = 0
    var fusedFrameCount: Int = 0
    var trackingStateText: String = "Initializing"
    var worldMappingStatusText: String = "Not Available"
    var scanQuality: ScanQuality = .poor

    // Debug logging overlay
    var debugLogs: [DebugLog] = []
    var showDebugOverlay: Bool = true
    private let maxDebugLogs = 100

    // MARK: - Debug Logging

    func addDebugLog(_ message: String, level: DebugLogLevel = .info, tag: String = "App") {
        let log = DebugLog(timestamp: Date(), level: level, tag: tag, message: message)
        debugLogs.append(log)

        if debugLogs.count > maxDebugLogs {
            debugLogs.removeFirst()
        }

        // Send to backend via DebugStreamService
        #if DEBUG
        if DebugSettings.shared.debugStreamEnabled {
            DebugStreamService.shared.logEvent(
                DebugEvent(
                    category: .logs,
                    type: "app_log",
                    data: [
                        "level": level.rawValue,
                        "tag": tag,
                        "message": message
                    ],
                    sessionId: session.id.uuidString
                )
            )
        }
        #endif
    }

    var canStartScanning: Bool {
        if isMockMode {
            return true
        }
        return arSessionManager.sessionState == .running &&
        arSessionManager.trackingState == .normal
    }

    // Processing state
    var processingState: ScanProcessingState {
        processingService.state
    }

    // Mock mode
    var isMockMode: Bool {
        // On real device with LiDAR, always use real AR - ignore mock mode setting
        if DeviceCapabilities.hasLiDAR {
            return false
        }
        return MockDataProvider.isMockModeEnabled
    }

    // MARK: - Session

    let session: ScanSession

    /// The scan mode (exterior uses GPS/heading, interior/object has different configs)
    let scanMode: ScanMode

    // MARK: - Dependencies

    private let arSessionManager: ARSessionManager
    private let mockARSessionManager = MockARSessionManager()
    private let meshProcessor = MeshAnchorProcessor()
    private let pointCloudExtractor = PointCloudExtractor()
    let processingService: ScanProcessingService

    // Depth fusion components
    private let depthFusionProcessor: DepthFusionProcessor
    private let highResExtractor: HighResPointCloudExtractor

    // Coverage analysis
    let coverageAnalyzer = CoverageAnalyzer()

    // Session persistence
    private let sessionPersistence = ScanSessionPersistence()

    private var scanStartTime: Date?
    private var frameCounter: Int = 0
    private let depthFusionEnabled: Bool

    // Auto-save timer
    private var autoSaveTask: Task<Void, Never>?
    private let autoSaveInterval: TimeInterval = 30

    // Debug stream throttle
    #if DEBUG
    private var lastDebugEventTime: TimeInterval = 0
    private let debugEventInterval: TimeInterval = 2.0
    #endif

    // Cached CIContext for texture capture (expensive to create)
    // Using nonisolated(unsafe) to avoid @Observable macro issues with lazy
    private nonisolated(unsafe) static let sharedCIContext: CIContext = {
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    // MARK: - Initialization

    init(
        session: ScanSession = ScanSession(),
        mode: ScanMode = .exterior,
        depthFusionEnabled: Bool = false  // DISABLED - focus on basic functionality first
    ) {
        self.session = session
        self.scanMode = mode
        self.arSessionManager = ARSessionManager()
        self.processingService = ScanProcessingService()
        self.depthFusionProcessor = DepthFusionProcessor()
        self.highResExtractor = HighResPointCloudExtractor()
        self.depthFusionEnabled = depthFusionEnabled

        // Configure AR session manager based on scan mode
        arSessionManager.scanMode = mode

        // Setup mock mode callbacks if enabled
        setupMockModeCallbacks()
    }

    // MARK: - Mock Mode Setup

    private func setupMockModeCallbacks() {
        mockARSessionManager.onFrameUpdate = { [weak self] frame in
            Task { @MainActor in
                self?.handleMockFrameUpdate(frame)
            }
        }

        mockARSessionManager.onMeshUpdate = { [weak self] mesh in
            Task { @MainActor in
                self?.handleMockMeshUpdate(mesh)
            }
        }

        mockARSessionManager.onTrackingStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.trackingStateText = state
            }
        }
    }

    private func handleMockFrameUpdate(_ frame: MockARSessionManager.MockARFrame) {
        guard isScanning else { return }

        frameCounter += 1
        fusedFrameCount = frameCounter

        // Add mock point cloud data incrementally
        if let pc = frame.pointCloud {
            if session.pointCloud == nil {
                session.pointCloud = pc
            } else {
                // Merge point clouds
                let existingPoints = session.pointCloud?.points ?? []
                let newPoints = existingPoints + pc.points
                session.pointCloud = PointCloud(points: newPoints, colors: nil, confidences: nil)
            }
            pointCount = session.pointCloud?.pointCount ?? 0
        }

        // Update scan quality based on progress
        let progress = mockARSessionManager.currentScanProgress
        if progress > 0.7 {
            scanQuality = .excellent
        } else if progress > 0.4 {
            scanQuality = .good
        } else if progress > 0.2 {
            scanQuality = .fair
        } else {
            scanQuality = .poor
        }
    }

    private func handleMockMeshUpdate(_ mesh: MeshData) {
        session.addMesh(mesh)
        meshFaceCount = session.faceCount
    }

    // MARK: - AR Session Setup

    func setupARSession(with arView: ARView) {
        // In mock mode, just update UI state without actual AR session
        if isMockMode {
            trackingStateText = "Mock Mode Ready"
            worldMappingStatusText = "Simulated"
            scanQuality = .fair
            return
        }

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

        // Request camera permission before starting AR session
        Task {
            let granted = await DeviceCapabilities.requestCameraPermission()
            guard granted else {
                self.errorMessage = "Přístup ke kameře je vyžadován pro skenování. Povolte jej v Nastavení."
                self.showError = true
                return
            }

            // Start session after permission granted
            arSessionManager.startSession()

            // Set initial visualization
            arSessionManager.setMeshVisualization(enabled: showMeshVisualization)
        }
    }

    // MARK: - Scanning Control

    func startScanning() {
        guard canStartScanning else { return }

        // Reset session data if starting fresh (not resuming)
        if session.state == .idle || session.state == .completed || session.state == .failed {
            session.reset()
            coverageAnalyzer.reset()
            // Generate unique scan name
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM HH:mm"
            session.name = "Sken \(dateFormatter.string(from: Date()))"
        }

        isScanning = true
        scanStartTime = Date()
        frameCounter = 0
        fusedFrameCount = 0
        pointCount = 0
        meshFaceCount = 0
        session.startScanning()

        // Start debug streaming
        #if DEBUG
        if DebugSettings.shared.debugStreamEnabled {
            DebugStreamService.shared.startStreaming(sessionId: session.id.uuidString)
            addDebugLog("Debug stream started", level: .network, tag: "Stream")
        }
        #endif

        addDebugLog("Scan started: \(session.name)", level: .info, tag: "Scan")

        // Update ML models status
        updateActiveMLModels()

        if isMockMode {
            mockARSessionManager.startSession()
            trackingStateText = "Mock Mode"
            worldMappingStatusText = "Simulated"
        } else {
            processingService.startScanning()
            startAutoSave()
        }
    }

    func pauseScanning() {
        isScanning = false
        session.pauseScanning()
        addDebugLog("Scan paused", level: .info, tag: "Scan")

        if isMockMode {
            mockARSessionManager.pauseSession()
        }
    }

    func resumeScanning() {
        guard session.state == .paused else { return }
        isScanning = true
        session.resumeScanning()
        addDebugLog("Scan resumed", level: .info, tag: "Scan")

        if isMockMode {
            mockARSessionManager.resumeSession()
        }
    }

    func stopScanning() {
        isScanning = false
        session.stopScanning()
        stopAutoSave()

        addDebugLog("Scan stopped, depth frames: \(session.depthFrames.count)", level: .info, tag: "Scan")

        // Stop debug streaming
        #if DEBUG
        if DebugSettings.shared.debugStreamEnabled {
            addDebugLog("Debug stream stopping", level: .network, tag: "Stream")
            DebugStreamService.shared.stopStreaming()
        }
        #endif

        if isMockMode {
            mockARSessionManager.stopSession()
            // Use mock data for final result
            if session.pointCloud == nil {
                session.pointCloud = MockDataProvider.shared.generateRoomPointCloud()
            }
        } else {
            // Generate final point cloud from all mesh anchors
            let meshAnchors = arSessionManager.getAllMeshAnchors()
            session.pointCloud = pointCloudExtractor.extractPointCloud(from: meshAnchors)

            // Save final session state
            Task {
                await saveCurrentProgress()
            }

            // Raw Data Mode: Upload to debug backend
            if DebugSettings.shared.rawDataModeEnabled {
                Task {
                    await uploadRawData(meshAnchors: meshAnchors)
                }
            }
        }

        showPreview = true
    }

    // MARK: - Raw Data Upload

    /// Upload raw scan data to debug backend
    private func uploadRawData(meshAnchors: [ARMeshAnchor]) async {
        guard let uploader = RawDataUploader.create(settings: DebugSettings.shared) else {
            print("RawDataUploader: Failed to create uploader - invalid configuration")
            return
        }

        print("RawDataUploader: Starting upload of \(meshAnchors.count) mesh anchors, \(session.textureFrames.count) texture frames")

        do {
            let result = try await uploader.uploadRawScan(
                meshAnchors: meshAnchors,
                textureFrames: session.textureFrames,
                depthFrames: session.depthFrames,
                sessionName: session.name,
                onProgress: { progress in
                    print("RawDataUploader: Progress \(Int(progress * 100))%")
                }
            )

            print("RawDataUploader: Upload completed!")
            print("  - Scan ID: \(result.scanId)")
            print("  - Uploaded: \(ByteCountFormatter.string(fromByteCount: result.uploadedBytes, countStyle: .file))")
            print("  - Duration: \(String(format: "%.1f", result.durationSeconds))s")
            print("  - Mesh anchors: \(result.meshAnchorCount)")
            print("  - Texture frames: \(result.textureFrameCount)")
        } catch {
            print("RawDataUploader: Upload failed - \(error.localizedDescription)")
        }
    }

    /// Stop scanning and start full processing pipeline (local + backend)
    func stopAndProcess() async {
        isScanning = false
        session.stopScanning()
        showProcessing = true

        do {
            // Local processing
            let result = try await processingService.stopScanning()
            session.pointCloud = result.pointCloud

            // Upload to backend
            let scanId = try await processingService.uploadToBackend(result)

            // Start server processing
            try await processingService.startServerProcessing(scanId: scanId)

            // Download will be triggered by WebSocket when complete
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            showProcessing = false
        }
    }

    func cancelScanning() {
        isScanning = false
        arSessionManager.stopSession()

        // Stop debug streaming
        #if DEBUG
        DebugStreamService.shared.stopStreaming()
        #endif
    }

    // MARK: - Scene Phase Handling

    /// Handle app lifecycle changes to prevent camera black screen
    func handleScenePhaseChange(to newPhase: ScenePhase) {
        guard !isMockMode else { return }

        switch newPhase {
        case .active:
            // Resume AR session when app returns to foreground
            let state = arSessionManager.sessionState
            if state == .interrupted || state == .paused {
                arSessionManager.resumeSession()
                addDebugLog("AR session resumed (app active)", level: .info, tag: "AR")
            }
        case .inactive, .background:
            // Pause AR session to prevent black screen on return
            if arSessionManager.sessionState == .running {
                arSessionManager.pauseSession()
                addDebugLog("AR session paused (app backgrounded)", level: .info, tag: "AR")
            }
        @unknown default:
            break
        }
    }

    // MARK: - Frame Handling

    private func handleFrameUpdate(_ frame: ARFrame) {
        // Update world mapping status
        updateWorldMappingStatus(frame.worldMappingStatus)

        // Always update camera transform for coverage overlay
        currentCameraTransform = frame.camera.transform

        guard isScanning else { return }

        // Record camera trajectory
        session.addCameraPosition(frame.camera.transform)

        // Update scan quality
        updateScanQuality(frame)

        // Process frame
        frameCounter += 1

        // Capture texture frames (every 10th frame)
        captureTextureFrame(frame)

        // Capture depth frames (every 5th frame)
        captureDepthFrame(frame)

        // Update coverage analysis (every 5th frame)
        if frameCounter % 5 == 0 {
            updateCoverageAnalysis()
        }

        // Check memory pressure and log status periodically
        if frameCounter % 30 == 0 {
            checkMemoryPressure()
            addDebugLog("Frame \(frameCounter), mesh: \(meshFaceCount), pts: \(pointCount)", level: .debug, tag: "AR")
        }

        // Send periodic debug stream events (throttled to every ~2s)
        #if DEBUG
        if DebugSettings.shared.debugStreamEnabled {
            let currentTime = frame.timestamp
            if currentTime - lastDebugEventTime >= debugEventInterval {
                lastDebugEventTime = currentTime
                DebugStreamService.shared.logAppState(
                    scanState: session.state.rawValue,
                    trackingState: trackingStateText,
                    pointCount: pointCount,
                    meshFaceCount: meshFaceCount,
                    memoryMB: PerformanceMonitor.shared.memoryUsageMB
                )
            }
        }
        #endif

        // Process depth fusion (every 3rd frame for performance)
        if depthFusionEnabled && frameCounter % 3 == 0 {
            isMLProcessing = true
            Task {
                await processFrameWithDepthFusion(frame)
                await MainActor.run {
                    isMLProcessing = false
                }
            }
        }
    }

    private func processFrameWithDepthFusion(_ frame: ARFrame) async {
        do {
            // Process frame through depth fusion pipeline
            try await processingService.processFrame(frame)

            // Update UI stats
            if let stats = processingService.processingStats {
                fusedFrameCount = stats.fusedFrameCount
                pointCount = stats.pointCount
            }
        } catch {
            // Log error but don't interrupt scanning
            print("Depth fusion error: \(error.localizedDescription)")
        }
    }

    private func handleMeshUpdate(_ meshAnchor: ARMeshAnchor) {
        guard isScanning else { return }

        // Process mesh anchor
        let meshData = meshProcessor.extractMeshData(from: meshAnchor)
        session.addMesh(meshData)

        // Update statistics
        updateStatistics()

        #if DEBUG
        if DebugSettings.shared.debugStreamEnabled {
            DebugStreamService.shared.logMeshAnchorEvent(meshAnchor, type: "updated")
        }
        #endif
    }

    // MARK: - State Updates

    private func updateTrackingState(_ state: ARCamera.TrackingState) {
        trackingStateText = state.displayName

        #if DEBUG
        if DebugSettings.shared.debugStreamEnabled {
            DebugStreamService.shared.logARTrackingChange(state)
        }
        #endif
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

    // MARK: - Resume Session

    /// Check for resumable sessions and show sheet if any exist
    func checkForResumableSessions() {
        Task {
            let sessions = await sessionPersistence.listSavedSessions()
            if !sessions.isEmpty {
                resumableSessions = sessions
                showResumeSheet = true
            }
        }
    }

    /// Resume a previously saved session
    func resumeSession(sessionId: UUID) async {
        do {
            // Load the session
            let loadedSession = try await sessionPersistence.loadSession(id: sessionId)

            // Load world map if available
            do {
                let worldMap = try await sessionPersistence.loadWorldMap(sessionId: sessionId)
                arSessionManager.resumeWithWorldMap(worldMap)
            } catch {
                #if DEBUG
                DebugStreamService.shared.trackError("Failed to load world map: \(error)", screen: "Scanning")
                #endif
                print("Warning: Could not load world map: \(error.localizedDescription)")
                // Continue without world map - user can still scan
            }

            // Load coverage data if available
            do {
                if let coverageData = try await sessionPersistence.loadCoverageGrid(sessionId: sessionId) {
                    try coverageAnalyzer.restoreCoverageGrid(from: coverageData)
                }
            } catch {
                #if DEBUG
                DebugStreamService.shared.trackError("Failed to load coverage grid: \(error)", screen: "Scanning")
                #endif
                print("Warning: Could not load coverage grid: \(error.localizedDescription)")
                // Continue without coverage data - it will rebuild as user scans
            }

            showResumeSheet = false
            trackingStateText = "Relocalizing..."
        } catch {
            #if DEBUG
            DebugStreamService.shared.trackError("Failed to resume session: \(error)", screen: "Scanning")
            #endif
            errorMessage = "Nepodařilo se obnovit session: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Start a new scan (dismiss resume sheet)
    func startNewScan() {
        showResumeSheet = false
        // Session is already created in init
    }

    /// Delete a saved session
    func deleteSession(sessionId: UUID) async {
        do {
            try await sessionPersistence.deleteSession(id: sessionId)
            resumableSessions.removeAll { $0.id == sessionId }
        } catch {
            #if DEBUG
            DebugStreamService.shared.trackError("Failed to delete session: \(error)", screen: "Scanning")
            #endif
            errorMessage = "Nepodařilo se smazat session: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Auto-Save

    private func startAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            while !Task.isCancelled && isScanning {
                try? await Task.sleep(for: .seconds(autoSaveInterval))
                guard isScanning else { break }

                await saveCurrentProgress()
            }
        }
    }

    private func stopAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }

    /// Clean up resources when view disappears
    func cleanup() {
        stopAutoSave()
        // Stop any ongoing processing
        if isScanning {
            pauseScanning()
        }
        #if DEBUG
        print("[Debug] ScanningViewModel cleanup called")
        #endif
    }

    private func saveCurrentProgress() async {
        do {
            // Save session checkpoint
            try await sessionPersistence.createCheckpoint(session: session)

            // Save world map if available
            if arSessionManager.canSaveWorldMap {
                let worldMap = try await arSessionManager.getCurrentWorldMap()
                try await sessionPersistence.saveWorldMap(worldMap, sessionId: session.id)
            }

            // Save coverage grid
            let coverageData = try coverageAnalyzer.serializeCoverageGrid()
            try await sessionPersistence.saveCoverageGrid(coverageData, sessionId: session.id)

        } catch {
            print("Auto-save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Coverage Analysis

    private func updateCoverageAnalysis() {
        guard isScanning else { return }

        let meshAnchors = arSessionManager.getAllMeshAnchors()
        coverageAnalyzer.updateCoverage(
            meshAnchors: meshAnchors,
            cameraTransform: currentCameraTransform
        )
    }

    // MARK: - Memory Monitoring

    private func checkMemoryPressure() {
        memoryPressure = DeviceCapabilities.memoryPressureLevel

        switch memoryPressure {
        case .critical:
            // Force save to disk and reduce quality
            Task {
                await saveCurrentProgress()
            }
            print("Critical memory pressure - saved progress")
        case .warning:
            print("Memory warning - consider reducing quality")
        case .normal:
            break
        }
    }

    // MARK: - Toggle Coverage Overlay

    func toggleCoverageOverlay() {
        showCoverageOverlay.toggle()
    }

    // MARK: - ML Model Status

    private func updateActiveMLModels() {
        var models: [String] = []

        // Check device capabilities for ML models
        if DeviceCapabilities.hasNeuralEngine {
            models.append("Neural Engine")
        }

        if depthFusionEnabled {
            models.append("Depth Fusion")
        }

        // Check if mesh correction model is available
        if processingService.isMeshCorrectionAvailable {
            models.append("Mesh Correction")
        }

        activeMLModels = models
    }

    // MARK: - Texture Frame Capture

    private func captureTextureFrame(_ frame: ARFrame) {
        guard isScanning else { return }

        // Capture every 10th frame for textures (balance quality vs storage)
        guard frameCounter % 10 == 0 else { return }

        // Get camera image
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Convert to JPEG data using cached CIContext
        guard let cgImage = Self.sharedCIContext.createCGImage(ciImage, from: ciImage.extent),
              let imageData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) else {
            return
        }

        // Create texture frame
        let textureFrame = TextureFrame(
            timestamp: frame.timestamp,
            imageData: imageData,
            resolution: CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                             height: CVPixelBufferGetHeight(pixelBuffer)),
            intrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            exposureDuration: frame.camera.exposureDuration,
            iso: nil // ISO not available from ARCamera
        )

        session.addTextureFrame(textureFrame)
    }

    // MARK: - Depth Frame Capture

    private func captureDepthFrame(_ frame: ARFrame) {
        guard isScanning else { return }
        guard DebugSettings.shared.includeDepthMaps else { return }
        guard frameCounter % 5 == 0 else { return }  // ~12 FPS

        // Use existing DepthFrame initializer from ARFrame
        guard let depthFrame = DepthFrame(from: frame) else {
            return
        }

        session.addDepthFrame(depthFrame)

        // Log every 10th captured depth frame
        if session.depthFrames.count % 10 == 0 {
            let range = depthFrame.depthRange
            addDebugLog("Depth \(session.depthFrames.count): \(depthFrame.width)x\(depthFrame.height), range: \(String(format: "%.1f", range.min))-\(String(format: "%.1f", range.max))m", level: .debug, tag: "Depth")
        }
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
