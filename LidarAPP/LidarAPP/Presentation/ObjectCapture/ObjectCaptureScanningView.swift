import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - Object Capture Scanning View

struct ObjectCaptureScanningView: View {
    @StateObject private var viewModel = ObjectCaptureViewModel()
    @State private var showResults = false
    @Environment(\.dismiss) private var dismiss

    var onScanCompleted: ((ScanModel, ScanSession) -> Void)?

    /// Use real AR on devices with LiDAR, mock mode only on simulator
    private var shouldUseMockMode: Bool {
        // On real device with LiDAR, always use real AR
        if DeviceCapabilities.hasLiDAR {
            return false
        }
        return MockDataProvider.isMockModeEnabled
    }

    var body: some View {
        ZStack {
            // Object Capture view - uses LiDAR AR view for object scanning
            if shouldUseMockMode {
                // Mock mode only - simulator or device without LiDAR
                MockObjectCaptureView(viewModel: viewModel)
                    .ignoresSafeArea()
            } else if ObjectCaptureService.isSupported {
                // Real device with LiDAR - use actual AR view
                ObjectCaptureARView(viewModel: viewModel)
                    .ignoresSafeArea()
            } else {
                // Fallback for unsupported devices
                unsupportedView
            }

            // Overlay UI
            VStack {
                // Top bar
                topBar

                Spacer()

                // Guidance indicators
                if viewModel.isCapturing {
                    guidanceView
                }

                // Capture stats
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
            ObjectCaptureResultsView(viewModel: viewModel) { scanModel, session in
                onScanCompleted?(scanModel, session)
                dismiss()
            }
        }
    }

    private var unsupportedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Object Capture nepodporován")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Tato funkce vyžaduje iOS 17+ a LiDAR senzor.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Zavřít") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
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
                    Text("Obejděte objekt dokola")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            // Help button
            Button(action: { /* show help */ }) {
                Image(systemName: "questionmark.circle")
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

    private var guidanceView: some View {
        VStack(spacing: 12) {
            // Orbit progress indicator
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.orbitProgress))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "cube.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }

            Text(viewModel.guidanceText)
                .font(.callout)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 40)
    }

    private var captureStatsBar: some View {
        HStack(spacing: 24) {
            VStack(spacing: 4) {
                Image(systemName: "photo.stack")
                    .font(.title3)
                Text("\(viewModel.imageCount)")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Snímky")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.3))

            VStack(spacing: 4) {
                Image(systemName: "rotate.3d")
                    .font(.title3)
                Text("\(Int(viewModel.orbitProgress * 100))%")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Orbita")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.3))

            VStack(spacing: 4) {
                Image(systemName: qualityIcon)
                    .font(.title3)
                    .foregroundStyle(qualityColor)
                Text(viewModel.quality.displayName)
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Kvalita")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

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

    private var controlsBar: some View {
        HStack(spacing: 40) {
            // Flip camera (placeholder)
            VStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                Text("Flip")
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: 50)

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
                    } else if viewModel.status == .processing {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 65, height: 65)
                    }
                }
            }
            .disabled(viewModel.status == .processing)

            // Auto-capture toggle
            VStack {
                Image(systemName: viewModel.autoCapture ? "a.circle.fill" : "a.circle")
                    .font(.title2)
                Text("Auto")
                    .font(.caption2)
            }
            .foregroundStyle(viewModel.autoCapture ? .white : .white.opacity(0.5))
            .frame(width: 50)
            .onTapGesture {
                viewModel.autoCapture.toggle()
            }
        }
        .padding(.vertical, 30)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Object Capture View Model

@MainActor
class ObjectCaptureViewModel: ObservableObject {
    @Published var status: ObjectCaptureStatus = .idle
    @Published var progress: Float = 0
    @Published var imageCount: Int = 0
    @Published var orbitProgress: Float = 0
    @Published var quality: CaptureQuality = .poor
    @Published var guidanceText: String = "Namířte na objekt"
    @Published var autoCapture: Bool = true
    @Published var showError = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private var mockTimer: Timer?

    var isCapturing: Bool {
        status == .capturing
    }

    var isSupported: Bool {
        ObjectCaptureService.isSupported || MockDataProvider.isMockModeEnabled
    }

    init() {
        setupBindings()
    }

    private func setupBindings() {
        if #available(iOS 17.0, *), ObjectCaptureService.isSupported {
            let service = ObjectCaptureService.shared

            service.captureStatus
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    self?.status = status
                    if case .failed(let message) = status {
                        self?.errorMessage = message
                        self?.showError = true
                    }
                }
                .store(in: &cancellables)

            service.captureProgress
                .receive(on: DispatchQueue.main)
                .sink { [weak self] progress in
                    self?.progress = progress
                }
                .store(in: &cancellables)

            service.imageCount
                .receive(on: DispatchQueue.main)
                .sink { [weak self] count in
                    self?.imageCount = count
                    self?.updateQualityAndGuidance()
                }
                .store(in: &cancellables)
        }
    }

    private func updateQualityAndGuidance() {
        // Update quality based on image count
        if imageCount < 10 {
            quality = .poor
            guidanceText = "Pokračujte ve skenování"
        } else if imageCount < 25 {
            quality = .fair
            guidanceText = "Zachyťte více úhlů"
        } else if imageCount < 40 {
            quality = .good
            guidanceText = "Dobrá práce, pokračujte"
        } else {
            quality = .excellent
            guidanceText = "Výborné! Můžete dokončit"
        }

        // Update orbit progress
        orbitProgress = min(Float(imageCount) / 50.0, 1.0)
    }

    /// Use real AR on devices with LiDAR
    private var shouldUseMockMode: Bool {
        if DeviceCapabilities.hasLiDAR { return false }
        return MockDataProvider.isMockModeEnabled
    }

    func startCapture() async {
        if shouldUseMockMode {
            // Start mock capture (simulator only)
            await startMockCapture()
            return
        }

        guard isSupported else {
            errorMessage = "Object Capture není na tomto zařízení podporován"
            showError = true
            return
        }

        // Real device: AR session is managed by ObjectCaptureARView
        // Status will be updated to .capturing by the AR session delegate
        // when tracking becomes normal
        status = .preparing
    }

    func stopCapture() async {
        if shouldUseMockMode {
            stopMockCapture()
            return
        }

        // Real device: just update status, AR session cleanup handled by view
        status = .completed(nil)
    }

    func cancelCapture() {
        mockTimer?.invalidate()
        mockTimer = nil

        ObjectCaptureService.shared.cancelCapture()

        status = .idle
        imageCount = 0
        orbitProgress = 0
    }

    // MARK: - Mock Mode

    private func startMockCapture() async {
        status = .preparing

        try? await Task.sleep(nanoseconds: 500_000_000)

        status = .capturing
        imageCount = 0
        orbitProgress = 0
        quality = .poor

        // Simulate capturing with timer
        mockTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.status == .capturing else { return }

                self.imageCount += 1
                self.orbitProgress = min(Float(self.imageCount) / 50.0, 1.0)
                self.updateQualityAndGuidance()
            }
        }
    }

    private func stopMockCapture() {
        mockTimer?.invalidate()
        mockTimer = nil
        status = .completed(nil)
    }

    func convertToSession() -> ScanSession {
        let session = ScanSession(name: "Object Scan")

        // Create mock point cloud for testing (simulator only)
        if shouldUseMockMode {
            session.pointCloud = MockDataProvider.shared.generateObjectPointCloud()
        }

        return session
    }
}

// MARK: - Capture Quality

enum CaptureQuality: Int, CaseIterable {
    case poor = 1
    case fair = 2
    case good = 3
    case excellent = 4

    var displayName: String {
        switch self {
        case .poor: return "Nízká"
        case .fair: return "Střední"
        case .good: return "Dobrá"
        case .excellent: return "Výborná"
        }
    }
}

// MARK: - Real Object Capture AR View
// Uses ARKit with LiDAR for real object scanning on device

struct ObjectCaptureARView: UIViewRepresentable {
    @ObservedObject var viewModel: ObjectCaptureViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR view for object scanning
        arView.automaticallyConfigureSession = false
        arView.renderOptions = [
            .disableMotionBlur,
            .disableDepthOfField
        ]

        // Configure AR session for object capture
        let configuration = ARWorldTrackingConfiguration()

        // Enable LiDAR mesh
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        // Enable depth
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }

        // Environment texturing for better textures
        configuration.environmentTexturing = .automatic

        // Use gravity alignment for object scanning
        configuration.worldAlignment = .gravity

        // Start session
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        arView.session.delegate = context.coordinator

        // NOTE: Scene understanding visualization disabled for object capture
        // to avoid overlaying the object being scanned.
        // The mesh is captured internally but not shown to user.

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Updates handled by coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, ARSessionDelegate {
        let viewModel: ObjectCaptureViewModel
        private var frameCount = 0
        private var hasStartedCapturing = false

        init(viewModel: ObjectCaptureViewModel) {
            self.viewModel = viewModel
        }

        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            Task { @MainActor in
                // Auto-start capturing once AR session is running
                if !hasStartedCapturing && frame.camera.trackingState == .normal {
                    hasStartedCapturing = true
                    viewModel.status = .capturing
                }

                guard viewModel.status == .capturing else { return }

                frameCount += 1

                // Capture frame every 15 frames (roughly 2 fps at 30fps input)
                if frameCount % 15 == 0 {
                    viewModel.imageCount += 1
                    viewModel.orbitProgress = min(Float(viewModel.imageCount) / 50.0, 1.0)

                    // Update quality based on image count
                    if viewModel.imageCount < 10 {
                        viewModel.quality = .poor
                        viewModel.guidanceText = "Pokračujte ve skenování"
                    } else if viewModel.imageCount < 25 {
                        viewModel.quality = .fair
                        viewModel.guidanceText = "Zachyťte více úhlů"
                    } else if viewModel.imageCount < 40 {
                        viewModel.quality = .good
                        viewModel.guidanceText = "Dobrá práce, pokračujte"
                    } else {
                        viewModel.quality = .excellent
                        viewModel.guidanceText = "Výborné! Můžete dokončit"
                    }
                }
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor in
                viewModel.status = .failed(error.localizedDescription)
                viewModel.errorMessage = error.localizedDescription
                viewModel.showError = true
            }
        }

        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in
                viewModel.guidanceText = "AR session přerušena"
            }
        }

        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor in
                viewModel.guidanceText = "Pokračujte ve skenování"
            }
        }
    }
}

// MARK: - Mock Object Capture View
// Note: Apple's ObjectCaptureSession/ObjectCaptureView is macOS-only.
// On iOS we use LiDAR + camera capture, then process on backend.

struct MockObjectCaptureView: View {
    @ObservedObject var viewModel: ObjectCaptureViewModel

    var body: some View {
        ZStack {
            // Simulated camera view
            Color.black

            // Grid overlay
            GeometryReader { geometry in
                Path { path in
                    let gridSize: CGFloat = 50
                    // Vertical lines
                    for x in stride(from: 0, to: geometry.size.width, by: gridSize) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                    // Horizontal lines
                    for y in stride(from: 0, to: geometry.size.height, by: gridSize) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            }

            // Center object indicator
            VStack {
                Spacer()

                ZStack {
                    // Object bounding box
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: 200, height: 200)

                    // Object placeholder
                    Image(systemName: "cube.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.green.opacity(0.5))
                }

                Spacer()
            }

            // "MOCK MODE" indicator
            VStack {
                Spacer()
                Text("SIMULACE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(.bottom, 200)
            }
        }
    }
}

// MARK: - Object Capture Results View

struct ObjectCaptureResultsView: View {
    @ObservedObject var viewModel: ObjectCaptureViewModel
    let onSave: (ScanModel, ScanSession) -> Void
    @State private var scanName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 3D Preview placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 250)

                    VStack(spacing: 12) {
                        Image(systemName: "cube.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.orange.opacity(0.5))

                        Text("\(viewModel.imageCount) snímků zachyceno")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Name field
                TextField("Název skenu", text: $scanName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                // Statistics
                VStack(spacing: 12) {
                    HStack {
                        ResultStatRow(label: "Zachycené snímky", value: "\(viewModel.imageCount)")
                        Spacer()
                        ResultStatRow(label: "Kvalita", value: viewModel.quality.displayName)
                    }

                    HStack {
                        ResultStatRow(label: "Pokrytí orbity", value: "\(Int(viewModel.orbitProgress * 100))%")
                        Spacer()
                        ResultStatRow(label: "Stav", value: "Připraveno")
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

                    Button(action: { dismiss() }) {
                        Text("Zahodit")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Object Capture")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func saveAndDismiss() {
        let session = viewModel.convertToSession()

        let name = scanName.isEmpty ? "Objekt \(Date().formatted(date: .abbreviated, time: .shortened))" : scanName
        session.name = name

        let scanModel = ScanModel(
            id: session.id.uuidString,
            name: name,
            createdAt: session.createdAt,
            thumbnail: nil,
            pointCount: session.pointCloud?.pointCount ?? 0,
            faceCount: session.faceCount,
            fileSize: Int64(viewModel.imageCount * 500_000), // Estimate ~500KB per image
            isProcessed: false,
            localURL: nil
        )

        onSave(scanModel, session)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    ObjectCaptureScanningView()
}
