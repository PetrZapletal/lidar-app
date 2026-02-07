import SwiftUI
import RealityKit

// MARK: - LiDAR Scanning Mode Adapter

/// Adapter that wraps existing ScanningViewModel to conform to ScanningModeProtocol
/// This preserves all existing LiDAR scanning functionality while enabling unified view usage
@MainActor
@Observable
final class LiDARScanningModeAdapter: ScanningModeProtocol {
    // MARK: - Wrapped ViewModel

    private let viewModel: ScanningViewModel
    private let mode: ScanMode
    private(set) var showResults = false

    // MARK: - Initialization

    init(mode: ScanMode = .exterior) {
        self.mode = mode
        self.viewModel = ScanningViewModel(mode: mode)
    }

    // MARK: - Protocol Conformance: Status

    var scanStatus: UnifiedScanStatus {
        if viewModel.showError {
            return .failed(viewModel.errorMessage ?? "Neznámá chyba")
        }
        if viewModel.showProcessing {
            return .processing
        }
        if viewModel.isScanning {
            return .scanning
        }
        if viewModel.canStartScanning {
            return .preparing
        }
        return .idle
    }

    var isScanning: Bool {
        viewModel.isScanning
    }

    var isPaused: Bool {
        viewModel.session.state == .paused
    }

    var canStartScanning: Bool {
        viewModel.canStartScanning
    }

    var statusSubtitle: String? {
        if isScanning {
            return "Skenujte pomalu a systematicky"
        }
        return nil
    }

    var captureButtonState: CaptureButtonState {
        if isScanning {
            return .paused  // LiDAR supports pause
        } else if canStartScanning {
            return .ready
        } else {
            return .disabled
        }
    }

    // MARK: - Protocol Conformance: Actions

    func startScanning() async {
        viewModel.startScanning()
    }

    func stopScanning() async {
        viewModel.stopScanning()
        showResults = true
    }

    func cancelScanning() {
        viewModel.cancelScanning()
    }

    // MARK: - LiDAR-Specific Actions

    func pauseScanning() {
        viewModel.pauseScanning()
    }

    func resumeScanning() {
        viewModel.resumeScanning()
    }

    func toggleMeshVisualization() {
        viewModel.toggleMeshVisualization()
    }

    func toggleCoverageOverlay() {
        viewModel.toggleCoverageOverlay()
    }

    /// Handle app lifecycle changes to prevent camera black screen
    func handleScenePhaseChange(to newPhase: ScenePhase) {
        viewModel.handleScenePhaseChange(to: newPhase)
    }

    // MARK: - Protocol Conformance: Views

    func makeMiddleContentView() -> some View {
        LiDARMiddleContentView(viewModel: viewModel)
    }

    func makeStatsView() -> some View {
        // LiDAR mode uses the quality indicator instead of stats grid
        Group {
            if isScanning {
                VStack(spacing: 8) {
                    ScanQualityIndicator(quality: viewModel.scanQuality)

                    // ML Models indicator when active
                    if !viewModel.activeMLModels.isEmpty {
                        MLModelsIndicator(models: viewModel.activeMLModels, isProcessing: viewModel.isMLProcessing)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    func makeLeftAccessory() -> some View {
        ControlAccessoryButton(
            icon: viewModel.showMeshVisualization ? "cube.fill" : "cube",
            label: "Mesh",
            action: { [weak self] in self?.toggleMeshVisualization() },
            isActive: viewModel.showMeshVisualization
        )
    }

    func makeRightAccessory() -> some View {
        Group {
            if isScanning {
                ControlAccessoryButton(
                    icon: "stop.fill",
                    label: "Stop",
                    action: {
                        Task { [weak self] in
                            await self?.stopScanning()
                        }
                    }
                )
            } else {
                ControlAccessoryButton(
                    icon: "xmark",
                    label: "Zavřít",
                    action: { [weak self] in self?.cancelScanning() }
                )
            }
        }
    }

    func makeTopBarRightContent() -> some View {
        // LiDAR has custom top bar, this provides additional buttons
        HStack(spacing: 8) {
            // Coverage toggle
            if isScanning {
                CircleButton(
                    icon: viewModel.showCoverageOverlay ? "map.fill" : "map",
                    action: { [weak self] in self?.toggleCoverageOverlay() },
                    accessibilityLabel: viewModel.showCoverageOverlay ? "Skrýt mapu pokrytí" : "Zobrazit mapu pokrytí"
                )
            }

            // Debug toggle (DEBUG only)
            #if DEBUG
            let vm = viewModel
            CircleButton(
                icon: vm.showDebugOverlay ? "text.bubble.fill" : "text.bubble",
                action: { vm.showDebugOverlay.toggle() },
                accessibilityLabel: "Debug log"
            )
            #endif
        }
    }

    // MARK: - Protocol Conformance: Results

    var hasResults: Bool {
        showResults
    }

    func makeResultsView(onSave: @escaping (ScanModel, ScanSession) -> Void, onDismiss: @escaping () -> Void) -> some View {
        LiDARResultsView(
            viewModel: viewModel,
            onSave: onSave,
            onDismiss: onDismiss
        )
    }

    // MARK: - Exposed Properties for Custom Top Bar

    var trackingStateText: String { viewModel.trackingStateText }
    var worldMappingStatusText: String { viewModel.worldMappingStatusText }
    var pointCount: Int { viewModel.pointCount }
    var meshFaceCount: Int { viewModel.meshFaceCount }
    var fusedFrameCount: Int { viewModel.fusedFrameCount }
    var scanDuration: String { viewModel.session.formattedDuration }
    var memoryPressure: MemoryPressureLevel { viewModel.memoryPressure }
    var isMockMode: Bool { viewModel.isMockMode }
}

// MARK: - LiDAR Middle Content View

/// Extracted middle content from original ScanningView
struct LiDARMiddleContentView: View {
    let viewModel: ScanningViewModel

    var body: some View {
        ZStack {
            // AR View (full screen)
            ARViewContainer(viewModel: viewModel)
                .ignoresSafeArea()

            // Coverage overlay (when scanning and enabled)
            if viewModel.isScanning && viewModel.showCoverageOverlay {
                CoverageOverlay(
                    coverageAnalyzer: viewModel.coverageAnalyzer,
                    cameraTransform: viewModel.currentCameraTransform,
                    isScanning: viewModel.isScanning
                )
                .allowsHitTesting(false)
            }

            // Guidance indicator for navigation (show top 3 gaps)
            if viewModel.isScanning && !viewModel.coverageAnalyzer.detectedGaps.isEmpty {
                GuidanceIndicatorsOverlay(
                    gaps: viewModel.coverageAnalyzer.detectedGaps,
                    cameraTransform: viewModel.currentCameraTransform
                )
            }

            // Debug Log Overlay - bottom right
            #if DEBUG
            if viewModel.showDebugOverlay && !viewModel.debugLogs.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        DebugLogOverlay(logs: viewModel.debugLogs)
                            .frame(maxWidth: 350)
                    }
                }
                .padding(.bottom, 120)
                .padding(.trailing, 12)
                .allowsHitTesting(false)
            }
            #endif

            // Mock mode warning banner
            if viewModel.isMockMode {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.black)
                        Text("MOCK MODE AKTIVNÍ")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .clipShape(Capsule())
                    .padding(.top, 50)

                    Spacer()
                }
            }
        }
    }
}

// MARK: - LiDAR Results View

struct LiDARResultsView: View {
    let viewModel: ScanningViewModel
    let onSave: (ScanModel, ScanSession) -> Void
    let onDismiss: () -> Void
    @State private var scanName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    Text("Vysledky skenovani")
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Stat cards grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        LiDARStatCard(
                            icon: "chart.bar.fill",
                            iconColor: .blue,
                            value: formatNumber(viewModel.pointCount),
                            label: "Bodu"
                        )

                        LiDARStatCard(
                            icon: "triangle.fill",
                            iconColor: .orange,
                            value: formatNumber(viewModel.meshFaceCount),
                            label: "Trojuhelniku"
                        )

                        LiDARStatCard(
                            icon: "clock.fill",
                            iconColor: .purple,
                            value: viewModel.session.formattedDuration,
                            label: "Doba skenovani"
                        )

                        LiDARStatCard(
                            icon: "star.fill",
                            iconColor: qualityColor,
                            value: qualityText,
                            label: "Kvalita"
                        )
                    }
                    .padding(.horizontal)

                    // Area scanned (if available)
                    if viewModel.session.areaScanned > 0 {
                        LiDARWideStatCard(
                            icon: "square.dashed",
                            iconColor: .green,
                            value: String(format: "%.1f m\u{00B2}", viewModel.session.areaScanned),
                            label: "Plocha"
                        )
                        .padding(.horizontal)
                    }

                    // Quality indicator bar
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Hustota bodu")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(pointDensityText)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(qualityColor.gradient)
                                    .frame(width: geometry.size.width * qualityProgress, height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nazev skenu")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Nazev skenu", text: $scanName)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 20)

                    // Action buttons
                    VStack(spacing: 12) {
                        Button(action: saveAndDismiss) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Ulozit")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button(action: onDismiss) {
                            Text("Zahodit")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("LiDAR sken")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Quality Helpers

    private var qualityText: String {
        switch viewModel.scanQuality {
        case .poor: return "Slaba"
        case .fair: return "Prijatelna"
        case .good: return "Dobra"
        case .excellent: return "Vynikajici"
        }
    }

    private var qualityColor: Color {
        viewModel.scanQuality.color
    }

    private var qualityProgress: CGFloat {
        switch viewModel.scanQuality {
        case .poor: return 0.2
        case .fair: return 0.45
        case .good: return 0.7
        case .excellent: return 1.0
        }
    }

    private var pointDensityText: String {
        let area = viewModel.session.areaScanned
        guard area > 0 else { return "N/A" }
        let density = Float(viewModel.pointCount) / area
        if density >= 1000 {
            return String(format: "%.0f b/m\u{00B2}", density)
        }
        return String(format: "%.0f b/m\u{00B2}", density)
    }

    // MARK: - Actions

    private func saveAndDismiss() {
        let session = viewModel.session
        let name = scanName.isEmpty ? "LiDAR \(Date().formatted(date: .abbreviated, time: .shortened))" : scanName
        session.name = name

        let scanModel = ScanModel(
            id: session.id.uuidString,
            name: name,
            createdAt: session.createdAt,
            thumbnail: nil,
            pointCount: session.pointCloud?.pointCount ?? viewModel.pointCount,
            faceCount: viewModel.meshFaceCount,
            fileSize: Int64(viewModel.pointCount * 12 + viewModel.meshFaceCount * 12),
            isProcessed: false,
            localURL: nil
        )

        onSave(scanModel, session)
        onDismiss()
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - LiDAR Stat Card

struct LiDARStatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - LiDAR Wide Stat Card

struct LiDARWideStatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Legacy LiDAR Stat Row (kept for compatibility)

struct LiDARStatRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ML Models Indicator

struct MLModelsIndicator: View {
    let models: [String]
    let isProcessing: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
            }

            ForEach(models, id: \.self) { model in
                Text(model)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
