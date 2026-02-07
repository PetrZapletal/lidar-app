import SwiftUI
import RoomPlan
import Combine

// MARK: - RoomPlan Scanning View

struct RoomPlanScanningView: View {
    @State private var viewModel = RoomPlanViewModel()
    @State private var showResults = false
    @Environment(\.dismiss) private var dismiss

    var onScanCompleted: ((ScanModel, ScanSession) -> Void)?

    /// Convert RoomCaptureStatus to UnifiedScanStatus for shared components
    private var unifiedStatus: UnifiedScanStatus {
        switch viewModel.status {
        case .idle: return .idle
        case .preparing: return .preparing
        case .capturing: return .scanning
        case .processing: return .processing
        case .completed: return .completed
        case .failed(let message): return .failed(message)
        }
    }

    /// Capture button state based on view model status
    private var captureButtonState: CaptureButtonState {
        switch viewModel.status {
        case .idle, .preparing: return .processing
        case .capturing: return .recording
        case .processing: return .processing
        case .completed: return .ready
        case .failed: return .disabled
        }
    }

    var body: some View {
        ZStack {
            // RoomPlan capture view
            RoomCaptureViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()

            // Overlay UI
            VStack {
                // Top bar - using shared component
                SharedTopBar(
                    status: unifiedStatus,
                    statusSubtitle: viewModel.isCapturing ? "Pohybujte se pomalu po místnosti" : nil,
                    onClose: {
                        viewModel.cancelCapture()
                        dismiss()
                    }
                ) {
                    CircleButton(
                        icon: "info.circle",
                        action: { /* show info */ },
                        accessibilityLabel: "Informace"
                    )
                }

                Spacer()

                // Stats bar - using shared component
                if viewModel.isCapturing {
                    StatisticsGrid(items: [
                        StatItem(icon: "square.3.layers.3d", value: "\(viewModel.roomCount)", label: "Místnosti"),
                        StatItem(icon: "rectangle.portrait", value: "\(viewModel.wallCount)", label: "Stěny"),
                        StatItem(icon: "door.left.hand.open", value: "\(viewModel.doorCount)", label: "Dveře"),
                        StatItem(icon: "window.ceiling", value: "\(viewModel.windowCount)", label: "Okna")
                    ])
                    .padding(.bottom, 16)
                }

                // Controls - using shared component
                SharedControlBar(
                    captureState: captureButtonState,
                    onCaptureTap: {
                        if viewModel.isCapturing {
                            Task {
                                await viewModel.stopCapture()
                                showResults = true
                            }
                        }
                    }
                ) {
                    // Left: Progress indicator
                    ProgressAccessory(
                        progress: viewModel.progress,
                        label: "Progress"
                    )
                } rightContent: {
                    // Right: Area indicator
                    StatsAccessory(
                        icon: "square.dashed",
                        value: String(format: "%.1f", viewModel.totalArea),
                        label: "m²"
                    )
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.startCapture()
            }
        }
        .onDisappear {
            viewModel.cancelCapture()
        }
        .alert("Chyba", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Neznámá chyba")
        }
        .fullScreenCover(isPresented: $showResults) {
            if let structure = viewModel.capturedStructure {
                RoomPlanResultsView(
                    structure: structure,
                    viewModel: viewModel
                ) { scanModel, session in
                    onScanCompleted?(scanModel, session)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Circular Progress View (kept for backward compatibility)

struct CircularProgressView: View {
    let progress: Float

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 4)

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - RoomPlan View Model

@MainActor
@Observable
final class RoomPlanViewModel {
    // MARK: - Observable State (no @Published needed with @Observable)
    private(set) var status: RoomCaptureStatus = .idle
    private(set) var progress: Float = 0
    private(set) var roomCount: Int = 0
    private(set) var wallCount: Int = 0
    private(set) var doorCount: Int = 0
    private(set) var windowCount: Int = 0
    private(set) var totalArea: Float = 0
    var showError = false
    var errorMessage: String?
    private(set) var capturedStructure: CapturedStructure?

    // MARK: - Private
    private let service = RoomPlanService.shared
    private var cancellables = Set<AnyCancellable>()

    var isCapturing: Bool {
        status == .capturing
    }

    var isSupported: Bool {
        service.isSupported
    }

    init() {
        setupBindings()
    }

    private func setupBindings() {
        service.captureStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.status = status
                if case .completed(let structure) = status {
                    self?.capturedStructure = structure
                } else if case .failed(let message) = status {
                    self?.errorMessage = message
                    self?.showError = true
                }
            }
            .store(in: &cancellables)

        service.scanProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progress = progress
            }
            .store(in: &cancellables)

        service.capturedRooms
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rooms in
                self?.updateStats(from: rooms)
            }
            .store(in: &cancellables)
    }

    private func updateStats(from rooms: [CapturedRoom]) {
        roomCount = rooms.count
        wallCount = rooms.reduce(0) { $0 + $1.walls.count }
        doorCount = rooms.reduce(0) { $0 + $1.doors.count }
        windowCount = rooms.reduce(0) { $0 + $1.windows.count }

        totalArea = rooms.reduce(0) { total, room in
            total + room.floors.reduce(0) { $0 + $1.dimensions.x * $1.dimensions.y }
        }
    }

    func startCapture() async {
        guard isSupported else {
            errorMessage = "RoomPlan není na tomto zařízení podporován"
            showError = true
            return
        }

        do {
            try await service.startCapture()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func stopCapture() async {
        capturedStructure = await service.stopCapture()
    }

    func cancelCapture() {
        service.cancelCapture()
    }

    func convertToSession() -> ScanSession? {
        guard let structure = capturedStructure else { return nil }
        return service.convertToScanSession(structure: structure)
    }
}

// MARK: - RoomCapture View Representable

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    // With @Observable, no property wrapper needed - just pass the reference
    let viewModel: RoomPlanViewModel

    func makeUIView(context: Context) -> RoomCaptureView {
        // Creates the RoomCaptureView and stores it in the service.
        // The view's built-in captureSession is used by the service for
        // delegate callbacks, ensuring the camera feed is properly connected.
        let view = RoomPlanService.shared.createCaptureView()
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        // Updates handled by the service via the view's captureSession
    }
}

// MARK: - RoomPlan Results View

struct RoomPlanResultsView: View {
    let structure: CapturedStructure
    // With @Observable, no property wrapper needed
    let viewModel: RoomPlanViewModel
    let onSave: (ScanModel, ScanSession) -> Void
    @State private var scanName = ""
    @Environment(\.dismiss) private var dismiss

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
                        ResultStatRow(label: "Místnosti", value: "\(statistics.roomCount)")
                        Spacer()
                        ResultStatRow(label: "Stěny", value: "\(statistics.wallCount)")
                    }

                    HStack {
                        ResultStatRow(label: "Dveře", value: "\(statistics.doorCount)")
                        Spacer()
                        ResultStatRow(label: "Okna", value: "\(statistics.windowCount)")
                    }

                    Divider()

                    HStack {
                        ResultStatRow(
                            label: "Plocha podlahy",
                            value: String(format: "%.2f m²", statistics.totalFloorArea)
                        )
                        Spacer()
                        ResultStatRow(
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

                    Button(action: { dismiss() }) {
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
            dismiss()
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
        dismiss()
    }
}

struct ResultStatRow: View {
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

// MARK: - Preview

#Preview {
    RoomPlanScanningView()
}
