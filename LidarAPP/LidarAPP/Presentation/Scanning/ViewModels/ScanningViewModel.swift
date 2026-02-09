import SwiftUI
import ARKit
import Combine
import simd

/// ViewModel for the scanning interface
@MainActor
@Observable
final class ScanningViewModel {

    // MARK: - Scan State

    enum ScanPhase: Equatable {
        case idle
        case scanning
        case paused
        case completed
    }

    private(set) var scanPhase: ScanPhase = .idle

    // MARK: - Observable State

    var showError: Bool = false
    var errorMessage: String?
    var showPreview: Bool = false

    // Statistics
    private(set) var scanDuration: TimeInterval = 0
    private(set) var pointCount: Int = 0
    private(set) var faceCount: Int = 0
    private(set) var coveragePercentage: Float = 0
    private(set) var trackingStateText: String = "Initializing"
    private(set) var scanQuality: ScanQuality = .poor

    // Debug overlay
    var showDebugOverlay: Bool = false
    private(set) var debugLogs: [DebugLogEntry] = []
    private let maxDebugLogs = 80

    // Memory
    private(set) var memoryWarning: Bool = false

    // MARK: - Session

    let session: ScanSession
    private(set) var selectedMode: ScanMode?

    // MARK: - Dependencies

    private let services: ServiceContainer
    private var meshSubscription: AnyCancellable?
    private var durationTimer: Timer?
    private var scanStartTime: Date?

    // MARK: - Initialization

    init(services: ServiceContainer) {
        self.services = services
        self.session = ScanSession()

        services.logger.info("ScanningViewModel initialized", category: .logCategoryScanning)
    }

    // MARK: - Mode Selection

    func selectMode(_ mode: ScanMode) {
        selectedMode = mode
        services.logger.debug("Scan mode selected: \(mode.rawValue)", category: .logCategoryScanning)
    }

    // MARK: - Scanning Control

    func startScan(mode: ScanMode) {
        guard scanPhase == .idle || scanPhase == .paused else { return }

        selectedMode = mode

        if scanPhase == .idle {
            session.reset()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM HH:mm"
            session.name = "Sken \(dateFormatter.string(from: Date()))"
        }

        do {
            try services.arSession.startSession(mode: mode)
            services.camera.startCapture()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            services.logger.error("Failed to start scan: \(error.localizedDescription)", category: .logCategoryScanning)
            return
        }

        scanPhase = .scanning
        session.startScanning()
        scanStartTime = Date()
        startDurationTimer()
        startMeshSubscription()
        services.performanceMonitor.startMonitoring()

        addDebugEntry("Scan started: \(session.name) [\(mode.rawValue)]", level: .info)
        services.logger.info("Scan started in mode: \(mode.rawValue)", category: .logCategoryScanning)
    }

    func pauseScan() {
        guard scanPhase == .scanning else { return }

        scanPhase = .paused
        session.pauseScanning()
        services.arSession.pauseSession()
        services.camera.stopCapture()
        stopDurationTimer()
        updateDuration()

        addDebugEntry("Scan paused at \(formattedDuration)", level: .info)
        services.logger.info("Scan paused", category: .logCategoryScanning)
    }

    func resumeScan() {
        guard scanPhase == .paused, let mode = selectedMode else { return }

        scanPhase = .scanning
        session.resumeScanning()
        services.arSession.resumeSession()
        services.camera.startCapture()
        scanStartTime = Date()
        startDurationTimer()

        addDebugEntry("Scan resumed", level: .info)
        services.logger.info("Scan resumed", category: .logCategoryScanning)
    }

    func stopScan() {
        guard scanPhase == .scanning || scanPhase == .paused else { return }

        // Pause AR session first to prevent buffer deallocation during extraction
        services.arSession.pauseSession()

        scanPhase = .completed
        session.stopScanning()
        services.camera.stopCapture()
        stopDurationTimer()
        updateDuration()
        meshSubscription?.cancel()
        meshSubscription = nil

        // Stop the AR session fully
        services.arSession.stopSession()
        services.performanceMonitor.stopMonitoring()

        addDebugEntry("Scan stopped - \(pointCount) pts, \(faceCount) faces, \(formattedDuration)", level: .info)
        services.logger.info(
            "Scan completed: points=\(pointCount), faces=\(faceCount), duration=\(formattedDuration)",
            category: .logCategoryScanning
        )

        showPreview = true
    }

    // MARK: - Scene Phase Handling

    func handleScenePhaseChange(to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            if scanPhase == .paused {
                addDebugEntry("App active - scan paused, tap resume to continue", level: .debug)
            }
        case .inactive, .background:
            if scanPhase == .scanning {
                pauseScan()
                addDebugEntry("Auto-paused: app entered background", level: .warning)
                services.logger.warning("Scan auto-paused due to background transition", category: .logCategoryScanning)
            }
        @unknown default:
            break
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        if scanPhase == .scanning {
            pauseScan()
        }
        stopDurationTimer()
        meshSubscription?.cancel()
        meshSubscription = nil
        services.performanceMonitor.stopMonitoring()
        services.logger.debug("ScanningViewModel cleanup", category: .logCategoryScanning)
    }

    // MARK: - Error Handling

    func dismissError() {
        showError = false
        errorMessage = nil
    }

    // MARK: - Computed Properties

    var formattedDuration: String {
        let minutes = Int(scanDuration) / 60
        let seconds = Int(scanDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedPointCount: String {
        formatNumber(pointCount)
    }

    var formattedFaceCount: String {
        formatNumber(faceCount)
    }

    var isScanning: Bool {
        scanPhase == .scanning
    }

    var canStartScanning: Bool {
        scanPhase == .idle || scanPhase == .paused
    }

    // MARK: - Private Methods

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDuration()
                self?.updateStatistics()
                self?.checkMemoryPressure()
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateDuration() {
        if let startTime = scanStartTime {
            scanDuration = session.scanDuration + Date().timeIntervalSince(startTime)
        }
    }

    private func updateStatistics() {
        pointCount = services.arSession.totalVertexCount
        faceCount = services.arSession.totalFaceCount

        if let trackingState = services.arSession.trackingState {
            trackingStateText = trackingState.displayName
            updateScanQuality(trackingState: trackingState)
        }
    }

    private func updateScanQuality(trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .normal:
            scanQuality = faceCount > 1000 ? .excellent : .good
        case .limited(let reason):
            switch reason {
            case .excessiveMotion, .insufficientFeatures:
                scanQuality = .fair
            default:
                scanQuality = .poor
            }
        case .notAvailable:
            scanQuality = .poor
        }
    }

    private func startMeshSubscription() {
        meshSubscription?.cancel()
        meshSubscription = services.arSession.meshAnchorsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] anchors in
                guard let self else { return }
                self.updateStatistics()
            }
    }

    private func checkMemoryPressure() {
        let monitor = services.performanceMonitor
        // Warn at high memory usage (above 1GB for app)
        let newWarning = monitor.memoryUsageMB > 1000
        if newWarning != memoryWarning {
            memoryWarning = newWarning
            if newWarning {
                addDebugEntry("Memory warning: \(monitor.memoryUsageMB)MB used", level: .warning)
                services.logger.warning("High memory usage: \(monitor.memoryUsageMB)MB", category: .logCategoryScanning)
            }
        }
    }

    // MARK: - Debug Logging

    private func addDebugEntry(_ message: String, level: DebugLogEntry.Level) {
        let entry = DebugLogEntry(timestamp: Date(), level: level, message: message)
        debugLogs.append(entry)
        if debugLogs.count > maxDebugLogs {
            debugLogs.removeFirst()
        }
    }

    // MARK: - Formatting

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.0fK", Double(number) / 1_000)
        }
        return "\(number)"
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

// MARK: - Debug Log Entry

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: Level
    let message: String

    enum Level: String {
        case debug
        case info
        case warning
        case error

        var color: Color {
            switch self {
            case .debug: return .cyan
            case .info: return .white
            case .warning: return .orange
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .debug: return "ant"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            }
        }
    }
}

// MARK: - ARCamera.TrackingState Display

extension ARCamera.TrackingState {
    var displayName: String {
        switch self {
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return "Limited: Movement"
            case .insufficientFeatures:
                return "Limited: Features"
            case .initializing:
                return "Initializing"
            case .relocalizing:
                return "Relocalizing"
            @unknown default:
                return "Limited"
            }
        case .normal:
            return "Normal"
        }
    }
}
