import SwiftUI
import RealityKit
import ARKit

// MARK: - Scanning View

struct ScanningView: View {
    @State private var viewModel: ScanningViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(services: ServiceContainer) {
        self._viewModel = State(initialValue: ScanningViewModel(services: services))
    }

    var body: some View {
        ZStack {
            if viewModel.selectedMode == nil {
                // Mode selection
                ModeSelectionView { mode in
                    viewModel.selectMode(mode)
                    viewModel.startScan(mode: mode)
                } onClose: {
                    dismiss()
                }
            } else {
                // AR scanning view
                scanningContent
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(to: newPhase)
        }
        .alert("Chyba skenovani", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "Neznama chyba")
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    @ViewBuilder
    private var scanningContent: some View {
        ZStack {
            // AR Camera preview (full screen)
            ARViewContainer()
                .ignoresSafeArea()

            // Coverage overlay (top right, during scanning)
            if viewModel.isScanning {
                CoverageOverlay(
                    coveragePercentage: viewModel.coveragePercentage,
                    pointCount: viewModel.formattedPointCount,
                    faceCount: viewModel.formattedFaceCount,
                    scanQuality: viewModel.scanQuality
                )
            }

            // Memory warning banner
            if viewModel.memoryWarning {
                VStack {
                    MemoryWarningBanner()
                        .padding(.top, 60)
                    Spacer()
                }
            }

            // Debug log overlay
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
                .padding(.bottom, 140)
                .padding(.trailing, 12)
                .allowsHitTesting(false)
            }
            #endif

            // Main UI overlay
            VStack(spacing: 0) {
                // Top bar
                SharedTopBar(
                    trackingState: viewModel.trackingStateText,
                    pointCount: viewModel.formattedPointCount,
                    faceCount: viewModel.formattedFaceCount,
                    scanDuration: viewModel.formattedDuration,
                    onClose: {
                        if viewModel.isScanning {
                            viewModel.pauseScan()
                        }
                        dismiss()
                    }
                )
                .padding(.top, 8)

                Spacer()

                // Quality indicator
                if viewModel.isScanning {
                    ScanQualityIndicator(quality: viewModel.scanQuality)
                        .padding(.bottom, 8)
                }

                // Statistics grid above controls
                if viewModel.isScanning || viewModel.scanPhase == .paused {
                    StatisticsGrid(items: [
                        StatItem(
                            icon: "point.3.filled.connected.trianglepath.dotted",
                            value: viewModel.formattedPointCount,
                            label: "Body"
                        ),
                        StatItem(
                            icon: "square.stack.3d.up",
                            value: viewModel.formattedFaceCount,
                            label: "Plochy"
                        ),
                        StatItem(
                            icon: "timer",
                            value: viewModel.formattedDuration,
                            label: "Cas"
                        )
                    ])
                    .padding(.bottom, 8)
                }

                // Bottom control bar
                SharedControlBar(
                    isScanning: viewModel.isScanning,
                    isPaused: viewModel.scanPhase == .paused,
                    onStart: {
                        if let mode = viewModel.selectedMode {
                            viewModel.startScan(mode: mode)
                        }
                    },
                    onPause: { viewModel.pauseScan() },
                    onResume: { viewModel.resumeScan() },
                    onStop: { viewModel.stopScan() },
                    onClose: { dismiss() }
                )
                .padding(.bottom, 30)
            }

            // Debug toggle button (top right, below top bar)
            #if DEBUG
            VStack {
                HStack {
                    Spacer()
                    Button(action: { viewModel.showDebugOverlay.toggle() }) {
                        Image(systemName: viewModel.showDebugOverlay ? "text.bubble.fill" : "text.bubble")
                            .font(.title3)
                            .foregroundStyle(viewModel.showDebugOverlay ? .green : .white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, 80)
                Spacer()
            }
            #endif
        }
        .fullScreenCover(isPresented: $viewModel.showPreview) {
            ScanCompletedView(session: viewModel.session) {
                dismiss()
            }
        }
    }
}

// MARK: - AR View Container

struct ARViewContainer: UIViewRepresentable {

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        arView.renderOptions = [
            .disableMotionBlur,
            .disableDepthOfField
        ]
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - Mode Selection View

struct ModeSelectionView: View {
    let onModeSelected: (ScanMode) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Vyberte rezim skenovani")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)

                ForEach(ScanMode.allCases, id: \.self) { mode in
                    ModeCard(mode: mode) {
                        onModeSelected(mode)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavrit") { onClose() }
                }
            }
        }
    }
}

struct ModeCard: View {
    let mode: ScanMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: mode.icon)
                    .font(.title)
                    .foregroundStyle(mode.color)
                    .frame(width: 60, height: 60)
                    .background(mode.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(mode.description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Memory Warning Banner

struct MemoryWarningBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("Vysoka spotreba pameti")
                .font(.caption)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.8), in: Capsule())
    }
}

// MARK: - Scan Completed View

struct ScanCompletedView: View {
    let session: ScanSession
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scanName: String

    init(session: ScanSession, onDismiss: @escaping () -> Void) {
        self.session = session
        self.onDismiss = onDismiss
        self._scanName = State(initialValue: session.name)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.gradient)

                Text("Sken dokoncen")
                    .font(.title)
                    .fontWeight(.bold)

                TextField("Nazev skenu", text: $scanName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                VStack(spacing: 8) {
                    StatRow(label: "Vrcholy", value: "\(session.vertexCount.formatted())")
                    StatRow(label: "Plochy", value: "\(session.faceCount.formatted())")
                    StatRow(label: "Doba skenu", value: session.formattedDuration)
                    StatRow(label: "Plocha", value: String(format: "%.2f m2", session.areaScanned))
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()

                Button(action: {
                    session.name = scanName.isEmpty
                        ? "Sken \(Date().formatted(date: .abbreviated, time: .shortened))"
                        : scanName
                    dismiss()
                    onDismiss()
                }) {
                    Text("Ulozit")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: {
                    dismiss()
                    onDismiss()
                }) {
                    Text("Zahodit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Nahled skenu")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    ScanningView(services: ServiceContainer())
}
