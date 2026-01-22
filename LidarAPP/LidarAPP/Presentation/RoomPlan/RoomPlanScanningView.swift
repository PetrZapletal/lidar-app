import SwiftUI
import RoomPlan
import Combine

// MARK: - RoomPlan Scanning View

struct RoomPlanScanningView: View {
    @StateObject private var viewModel = RoomPlanViewModel()
    @State private var showResults = false
    @Environment(\.dismiss) private var dismiss

    var onScanCompleted: ((ScanModel, ScanSession) -> Void)?

    var body: some View {
        ZStack {
            // RoomPlan capture view
            RoomCaptureViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()

            // Overlay UI
            VStack {
                // Top bar
                topBar

                Spacer()

                // Progress and stats
                if viewModel.isCapturing {
                    captureStatsBar
                }

                // Controls
                controlsBar
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

    private var topBar: some View {
        HStack {
            // Close button
            Button(action: {
                viewModel.cancelCapture()
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            // Status indicator
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(viewModel.status.displayName)
                        .font(.headline)
                }

                if viewModel.isCapturing {
                    Text("Pohybujte se pomalu po místnosti")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            // Info button
            Button(action: { /* show info */ }) {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding()
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .idle, .preparing: return .gray
        case .capturing: return .green
        case .processing: return .orange
        case .completed: return .blue
        case .failed: return .red
        }
    }

    private var captureStatsBar: some View {
        HStack(spacing: 20) {
            StatItem(icon: "square.3.layers.3d", value: "\(viewModel.roomCount)", label: "Místnosti")
            StatItem(icon: "rectangle.portrait", value: "\(viewModel.wallCount)", label: "Stěny")
            StatItem(icon: "door.left.hand.open", value: "\(viewModel.doorCount)", label: "Dveře")
            StatItem(icon: "window.ceiling", value: "\(viewModel.windowCount)", label: "Okna")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    private var controlsBar: some View {
        HStack(spacing: 40) {
            // Progress indicator
            VStack {
                CircularProgressView(progress: viewModel.progress)
                    .frame(width: 50, height: 50)
                Text("\(Int(viewModel.progress * 100))%")
                    .font(.caption2)
            }
            .foregroundStyle(.white)

            // Main capture button
            Button(action: {
                if viewModel.isCapturing {
                    Task {
                        await viewModel.stopCapture()
                        showResults = true
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)

                    if viewModel.isCapturing {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                            .frame(width: 35, height: 35)
                    } else {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    }
                }
            }
            .disabled(!viewModel.isCapturing)

            // Area indicator
            VStack {
                Image(systemName: "square.dashed")
                    .font(.title2)
                Text(String(format: "%.1f m²", viewModel.totalArea))
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .frame(width: 50)
        }
        .padding(.vertical, 30)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Circular Progress View

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
class RoomPlanViewModel: ObservableObject {
    @Published var status: RoomCaptureStatus = .idle
    @Published var progress: Float = 0
    @Published var roomCount: Int = 0
    @Published var wallCount: Int = 0
    @Published var doorCount: Int = 0
    @Published var windowCount: Int = 0
    @Published var totalArea: Float = 0
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var capturedStructure: CapturedStructure?

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
    @ObservedObject var viewModel: RoomPlanViewModel

    func makeUIView(context: Context) -> RoomCaptureView {
        RoomPlanService.shared.createCaptureView()
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        // Updates handled by the service
    }
}

// MARK: - RoomPlan Results View

struct RoomPlanResultsView: View {
    let structure: CapturedStructure
    @ObservedObject var viewModel: RoomPlanViewModel
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
