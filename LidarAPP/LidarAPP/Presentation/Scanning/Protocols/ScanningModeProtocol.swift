import SwiftUI

// MARK: - Scanning Mode Protocol

/// Protocol defining common interface for all scanning modes (LiDAR, RoomPlan, ObjectCapture)
/// Enables UnifiedScanningView to work with any scanning mode through a single interface
@MainActor
protocol ScanningModeProtocol: AnyObject, Observable {
    // MARK: - Status Properties

    /// Current unified status of the scanning session
    var scanStatus: UnifiedScanStatus { get }

    /// Whether scanning is currently in progress
    var isScanning: Bool { get }

    /// Whether scanning can be started (device ready, permissions granted, etc.)
    var canStartScanning: Bool { get }

    /// Optional subtitle text to show below status (e.g., "Move slowly around the room")
    var statusSubtitle: String? { get }

    /// Current capture button state for SharedControlBar
    var captureButtonState: CaptureButtonState { get }

    // MARK: - Scanning Control

    /// Start the scanning session
    func startScanning() async

    /// Stop the scanning session and prepare results
    func stopScanning() async

    /// Cancel the scanning session without saving
    func cancelScanning()

    // MARK: - View Builders

    /// The main content view specific to this scanning mode (AR view, camera feed, etc.)
    associatedtype MiddleContent: View
    @ViewBuilder func makeMiddleContentView() -> MiddleContent

    /// Statistics view showing mode-specific metrics (point count, room count, orbit progress, etc.)
    associatedtype StatsView: View
    @ViewBuilder func makeStatsView() -> StatsView

    /// Left accessory view for the control bar
    associatedtype LeftAccessory: View
    @ViewBuilder func makeLeftAccessory() -> LeftAccessory

    /// Right accessory view for the control bar
    associatedtype RightAccessory: View
    @ViewBuilder func makeRightAccessory() -> RightAccessory

    /// Additional right content for the top bar (info button, help button, etc.)
    associatedtype TopBarRightContent: View
    @ViewBuilder func makeTopBarRightContent() -> TopBarRightContent

    // MARK: - Results

    /// Whether results are ready to be shown
    var hasResults: Bool { get }

    /// Results view to show after scanning completes
    associatedtype ResultsView: View
    @ViewBuilder func makeResultsView(onSave: @escaping (ScanModel, ScanSession) -> Void, onDismiss: @escaping () -> Void) -> ResultsView
}

// MARK: - Default Implementations

extension ScanningModeProtocol {
    /// Default status subtitle based on scanning state
    var statusSubtitle: String? {
        isScanning ? nil : nil
    }

    /// Default: no results
    var hasResults: Bool {
        false
    }
}

// MARK: - Type Erased Wrapper

/// Type-erased wrapper for ScanningModeProtocol to enable dynamic dispatch
/// This allows storing different mode types in a single variable
@MainActor
final class AnyScanningMode: ScanningModeProtocol, Observable {
    private let _scanStatus: () -> UnifiedScanStatus
    private let _isScanning: () -> Bool
    private let _canStartScanning: () -> Bool
    private let _statusSubtitle: () -> String?
    private let _captureButtonState: () -> CaptureButtonState
    private let _startScanning: () async -> Void
    private let _stopScanning: () async -> Void
    private let _cancelScanning: () -> Void
    private let _hasResults: () -> Bool

    private let _makeMiddleContent: () -> AnyView
    private let _makeStats: () -> AnyView
    private let _makeLeftAccessory: () -> AnyView
    private let _makeRightAccessory: () -> AnyView
    private let _makeTopBarRightContent: () -> AnyView
    private let _makeResultsView: (@escaping (ScanModel, ScanSession) -> Void, @escaping () -> Void) -> AnyView

    init<Mode: ScanningModeProtocol>(_ mode: Mode) {
        _scanStatus = { mode.scanStatus }
        _isScanning = { mode.isScanning }
        _canStartScanning = { mode.canStartScanning }
        _statusSubtitle = { mode.statusSubtitle }
        _captureButtonState = { mode.captureButtonState }
        _startScanning = { await mode.startScanning() }
        _stopScanning = { await mode.stopScanning() }
        _cancelScanning = { mode.cancelScanning() }
        _hasResults = { mode.hasResults }

        _makeMiddleContent = { AnyView(mode.makeMiddleContentView()) }
        _makeStats = { AnyView(mode.makeStatsView()) }
        _makeLeftAccessory = { AnyView(mode.makeLeftAccessory()) }
        _makeRightAccessory = { AnyView(mode.makeRightAccessory()) }
        _makeTopBarRightContent = { AnyView(mode.makeTopBarRightContent()) }
        _makeResultsView = { onSave, onDismiss in AnyView(mode.makeResultsView(onSave: onSave, onDismiss: onDismiss)) }
    }

    var scanStatus: UnifiedScanStatus { _scanStatus() }
    var isScanning: Bool { _isScanning() }
    var canStartScanning: Bool { _canStartScanning() }
    var statusSubtitle: String? { _statusSubtitle() }
    var captureButtonState: CaptureButtonState { _captureButtonState() }
    var hasResults: Bool { _hasResults() }

    func startScanning() async { await _startScanning() }
    func stopScanning() async { await _stopScanning() }
    func cancelScanning() { _cancelScanning() }

    func makeMiddleContentView() -> AnyView { _makeMiddleContent() }
    func makeStatsView() -> AnyView { _makeStats() }
    func makeLeftAccessory() -> AnyView { _makeLeftAccessory() }
    func makeRightAccessory() -> AnyView { _makeRightAccessory() }
    func makeTopBarRightContent() -> AnyView { _makeTopBarRightContent() }
    func makeResultsView(onSave: @escaping (ScanModel, ScanSession) -> Void, onDismiss: @escaping () -> Void) -> AnyView {
        _makeResultsView(onSave, onDismiss)
    }
}
