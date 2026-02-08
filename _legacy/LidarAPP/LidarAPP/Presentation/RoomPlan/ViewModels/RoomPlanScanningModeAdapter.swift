import SwiftUI
import RoomPlan

// MARK: - RoomPlan Scanning Mode Adapter

/// Adapter that wraps RoomPlanViewModel to conform to ScanningModeProtocol
/// Enables RoomPlan scanning to work with UnifiedScanningView
@MainActor
@Observable
final class RoomPlanScanningModeAdapter: ScanningModeProtocol {
    // MARK: - Wrapped ViewModel

    private let viewModel: RoomPlanViewModel
    private(set) var showResults = false

    // MARK: - Initialization

    init() {
        self.viewModel = RoomPlanViewModel()
    }

    // MARK: - Protocol Conformance: Status

    var scanStatus: UnifiedScanStatus {
        switch viewModel.status {
        case .idle: return .idle
        case .preparing: return .preparing
        case .capturing: return .scanning
        case .processing: return .processing
        case .completed: return .completed
        case .failed(let message): return .failed(message)
        }
    }

    var isScanning: Bool {
        viewModel.isCapturing
    }

    var canStartScanning: Bool {
        viewModel.isSupported
    }

    var statusSubtitle: String? {
        isScanning ? "Pohybujte se pomalu po místnosti" : nil
    }

    var captureButtonState: CaptureButtonState {
        switch viewModel.status {
        case .idle, .preparing: return .processing
        case .capturing: return .recording
        case .processing: return .processing
        case .completed: return .ready
        case .failed: return .disabled
        }
    }

    // MARK: - Protocol Conformance: Actions

    func startScanning() async {
        await viewModel.startCapture()
    }

    func stopScanning() async {
        await viewModel.stopCapture()
        showResults = true
    }

    func cancelScanning() {
        viewModel.cancelCapture()
    }

    // MARK: - Protocol Conformance: Views

    func makeMiddleContentView() -> some View {
        RoomCaptureViewRepresentable(viewModel: viewModel)
    }

    func makeStatsView() -> some View {
        Group {
            if isScanning {
                StatisticsGrid(items: [
                    StatItem(icon: "square.3.layers.3d", value: "\(viewModel.roomCount)", label: "Místnosti"),
                    StatItem(icon: "rectangle.portrait", value: "\(viewModel.wallCount)", label: "Stěny"),
                    StatItem(icon: "door.left.hand.open", value: "\(viewModel.doorCount)", label: "Dveře"),
                    StatItem(icon: "window.ceiling", value: "\(viewModel.windowCount)", label: "Okna")
                ])
                .padding(.bottom, 16)
            }
        }
    }

    func makeLeftAccessory() -> some View {
        ProgressAccessory(
            progress: viewModel.progress,
            label: "Progress"
        )
    }

    func makeRightAccessory() -> some View {
        StatsAccessory(
            icon: "square.dashed",
            value: String(format: "%.1f", viewModel.totalArea),
            label: "m²"
        )
    }

    func makeTopBarRightContent() -> some View {
        CircleButton(
            icon: "info.circle",
            action: { /* show info */ },
            accessibilityLabel: "Informace"
        )
    }

    // MARK: - Protocol Conformance: Results

    var hasResults: Bool {
        showResults && viewModel.capturedStructure != nil
    }

    func makeResultsView(onSave: @escaping (ScanModel, ScanSession) -> Void, onDismiss: @escaping () -> Void) -> some View {
        Group {
            if let structure = viewModel.capturedStructure {
                RoomPlanAdapterResultsView(
                    structure: structure,
                    viewModel: viewModel,
                    onSave: onSave,
                    onDismiss: onDismiss
                )
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Error Handling

    var showError: Bool { viewModel.showError }
    var errorMessage: String? { viewModel.errorMessage }
}

// MARK: - RoomPlan Results View (Adapter Version)

struct RoomPlanAdapterResultsView: View {
    let structure: CapturedStructure
    let viewModel: RoomPlanViewModel
    let onSave: (ScanModel, ScanSession) -> Void
    let onDismiss: () -> Void
    @State private var scanName = ""

    private var statistics: RoomStatistics {
        RoomStatistics.from(structure: structure)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 3D Preview placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 200)

                    Image(systemName: "house.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue.opacity(0.5))
                }
                .padding(.horizontal)

                // Name field
                TextField("Název skenu", text: $scanName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                // Statistics
                VStack(spacing: 12) {
                    HStack {
                        RoomPlanStatRow(label: "Místnosti", value: "\(statistics.roomCount)")
                        Spacer()
                        RoomPlanStatRow(label: "Stěny", value: "\(statistics.wallCount)")
                    }

                    HStack {
                        RoomPlanStatRow(label: "Dveře", value: "\(statistics.doorCount)")
                        Spacer()
                        RoomPlanStatRow(label: "Okna", value: "\(statistics.windowCount)")
                    }

                    Divider()

                    HStack {
                        RoomPlanStatRow(
                            label: "Plocha podlahy",
                            value: String(format: "%.2f m²", statistics.totalFloorArea)
                        )
                        Spacer()
                        RoomPlanStatRow(
                            label: "Plocha stěn",
                            value: String(format: "%.2f m²", statistics.totalWallArea)
                        )
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: saveAndDismiss) {
                        Text("Uložit")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: onDismiss) {
                        Text("Zahodit")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("RoomPlan sken")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func saveAndDismiss() {
        guard let session = viewModel.convertToSession() else {
            onDismiss()
            return
        }

        let name = scanName.isEmpty ? "RoomPlan \(Date().formatted(date: .abbreviated, time: .shortened))" : scanName
        session.name = name

        let scanModel = ScanModel(
            id: session.id.uuidString,
            name: name,
            createdAt: session.createdAt,
            thumbnail: nil,
            pointCount: session.pointCloud?.pointCount ?? session.vertexCount,
            faceCount: session.faceCount,
            fileSize: Int64(session.vertexCount * 12 + session.faceCount * 12),
            isProcessed: true,
            localURL: nil
        )

        onSave(scanModel, session)
        onDismiss()
    }
}

struct RoomPlanStatRow: View {
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
