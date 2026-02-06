import SwiftUI
import RealityKit
import ARKit

// MARK: - Object Capture Scanning Mode Adapter

/// Adapter that wraps ObjectCaptureViewModel to conform to ScanningModeProtocol
/// Enables Object Capture scanning to work with UnifiedScanningView
@MainActor
@Observable
final class ObjectCaptureScanningModeAdapter: ScanningModeProtocol {
    // MARK: - Wrapped ViewModel

    private let viewModel: ObjectCaptureViewModel
    private(set) var showResults = false

    // MARK: - Initialization

    init() {
        self.viewModel = ObjectCaptureViewModel()
    }

    // MARK: - Protocol Conformance: Status

    var scanStatus: UnifiedScanStatus {
        switch viewModel.status {
        case .idle: return .idle
        case .preparing: return .preparing
        case .capturing: return .scanning
        case .processing: return .processing
        case .completed: return .completed
        case .failed(let message): return .failed(message ?? "Neznámá chyba")
        }
    }

    var isScanning: Bool {
        viewModel.isCapturing
    }

    var canStartScanning: Bool {
        viewModel.isSupported
    }

    var statusSubtitle: String? {
        isScanning ? "Obejděte objekt dokola" : nil
    }

    var captureButtonState: CaptureButtonState {
        switch viewModel.status {
        case .idle: return .ready
        case .preparing: return .processing
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

    // MARK: - Object Capture Specific Actions

    func toggleAutoCapture() {
        viewModel.autoCapture.toggle()
    }

    // MARK: - Protocol Conformance: Views

    func makeMiddleContentView() -> some View {
        ObjectCaptureMiddleContentView(viewModel: viewModel)
    }

    func makeStatsView() -> some View {
        Group {
            if isScanning {
                VStack(spacing: 8) {
                    // Orbit progress and guidance
                    ObjectCaptureGuidanceView(viewModel: viewModel)

                    // Statistics grid
                    StatisticsGrid(items: [
                        StatItem(icon: "photo.stack", value: "\(viewModel.imageCount)", label: "Snímky"),
                        StatItem(icon: "rotate.3d", value: "\(Int(viewModel.orbitProgress * 100))%", label: "Orbita"),
                        StatItem(icon: qualityIcon, value: viewModel.quality.displayName, label: "Kvalita", iconColor: qualityColor)
                    ])
                }
                .padding(.bottom, 16)
            }
        }
    }

    func makeLeftAccessory() -> some View {
        ControlAccessoryButton(
            icon: "arrow.triangle.2.circlepath",
            label: "Flip",
            action: { /* flip camera placeholder */ }
        )
    }

    func makeRightAccessory() -> some View {
        ControlAccessoryButton(
            icon: viewModel.autoCapture ? "a.circle.fill" : "a.circle",
            label: "Auto",
            action: { [weak self] in self?.toggleAutoCapture() },
            isActive: viewModel.autoCapture
        )
    }

    func makeTopBarRightContent() -> some View {
        CircleButton(
            icon: "questionmark.circle",
            action: { /* show help */ },
            accessibilityLabel: "Nápověda"
        )
    }

    // MARK: - Protocol Conformance: Results

    var hasResults: Bool {
        showResults
    }

    func makeResultsView(onSave: @escaping (ScanModel, ScanSession) -> Void, onDismiss: @escaping () -> Void) -> some View {
        ObjectCaptureAdapterResultsView(
            viewModel: viewModel,
            onSave: onSave,
            onDismiss: onDismiss
        )
    }

    // MARK: - Helper Properties

    private var qualityIcon: String {
        switch viewModel.quality {
        case .poor: return "exclamationmark.triangle"
        case .fair: return "checkmark"
        case .good: return "checkmark.circle"
        case .excellent: return "checkmark.circle.fill"
        }
    }

    private var qualityColor: Color {
        switch viewModel.quality {
        case .poor: return .red
        case .fair: return .orange
        case .good: return .yellow
        case .excellent: return .green
        }
    }

    // MARK: - Error Handling

    var showError: Bool { viewModel.showError }
    var errorMessage: String? { viewModel.errorMessage }
}

// MARK: - Object Capture Middle Content View

struct ObjectCaptureMiddleContentView: View {
    let viewModel: ObjectCaptureViewModel

    /// Use real AR on devices with LiDAR, mock mode only on simulator
    private var shouldUseMockMode: Bool {
        if DeviceCapabilities.hasLiDAR {
            return false
        }
        return !ObjectCaptureService.isSupported
    }

    var body: some View {
        Group {
            if shouldUseMockMode {
                MockObjectCaptureView(viewModel: viewModel)
            } else {
                ObjectCaptureARView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Object Capture Guidance View

struct ObjectCaptureGuidanceView: View {
    let viewModel: ObjectCaptureViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Orbit progress indicator
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.orbitProgress))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Image(systemName: "camera.rotate")
                        .font(.title2)
                    Text("\(Int(viewModel.orbitProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
            }

            // Guidance text
            Text(viewModel.guidanceText)
                .font(.subheadline)
                .foregroundStyle(.white)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 40)
    }
}

// MARK: - Object Capture Results View (Adapter Version)

struct ObjectCaptureAdapterResultsView: View {
    let viewModel: ObjectCaptureViewModel
    let onSave: (ScanModel, ScanSession) -> Void
    let onDismiss: () -> Void
    @State private var scanName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 3D Preview placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 200)

                    Image(systemName: "cube.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange.opacity(0.5))
                }
                .padding(.horizontal)

                // Name field
                TextField("Název skenu", text: $scanName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                // Statistics
                VStack(spacing: 12) {
                    HStack {
                        ObjectCaptureStatRow(label: "Snímky", value: "\(viewModel.imageCount)")
                        Spacer()
                        ObjectCaptureStatRow(label: "Orbita", value: "\(Int(viewModel.orbitProgress * 100))%")
                    }

                    HStack {
                        ObjectCaptureStatRow(label: "Kvalita", value: viewModel.quality.displayName)
                        Spacer()
                        ObjectCaptureStatRow(label: "Auto", value: viewModel.autoCapture ? "Ano" : "Ne")
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
                            .background(.orange.gradient)
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
            .navigationTitle("Object Capture sken")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func saveAndDismiss() {
        let session = viewModel.convertToSession()
        let name = scanName.isEmpty ? "Object \(Date().formatted(date: .abbreviated, time: .shortened))" : scanName
        session.name = name

        let scanModel = ScanModel(
            id: session.id.uuidString,
            name: name,
            createdAt: session.createdAt,
            thumbnail: nil,
            pointCount: session.pointCloud?.pointCount ?? viewModel.imageCount * 1000,
            faceCount: session.faceCount,
            fileSize: Int64(viewModel.imageCount * 50_000),
            isProcessed: false,
            localURL: nil
        )

        onSave(scanModel, session)
        onDismiss()
    }
}

struct ObjectCaptureStatRow: View {
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
