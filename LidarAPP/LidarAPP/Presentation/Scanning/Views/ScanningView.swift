import SwiftUI
import RealityKit

/// Main scanning interface view
struct ScanningView: View {
    @Bindable private var viewModel: ScanningViewModel
    @State private var showSettings = false
    @State private var showStopOptions = false
    @Environment(\.dismiss) private var dismiss

    /// The scan mode (exterior or generic LiDAR)
    let mode: ScanMode

    /// Callback when scan is completed and saved (returns both model metadata and session with 3D data)
    var onScanCompleted: ((ScanModel, ScanSession) -> Void)?

    init(mode: ScanMode = .exterior, onScanCompleted: ((ScanModel, ScanSession) -> Void)? = nil) {
        self.mode = mode
        self.onScanCompleted = onScanCompleted
        self._viewModel = Bindable(ScanningViewModel(mode: mode))
    }

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
                .padding(.bottom, 120)  // Above control buttons
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
                        Text("- Vypněte v Nastavení → Vývojář")
                            .font(.caption2)
                            .foregroundStyle(.black.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .clipShape(Capsule())
                    .padding(.top, 50)

                    Spacer()
                }
            }

            // Overlay UI
            VStack(spacing: 0) {
                // Top bar with status and settings
                HStack {
                    ScanningStatusBar(
                        trackingState: viewModel.trackingStateText,
                        worldMappingStatus: viewModel.worldMappingStatusText,
                        pointCount: viewModel.pointCount,
                        meshFaceCount: viewModel.meshFaceCount,
                        fusedFrameCount: viewModel.fusedFrameCount,
                        scanDuration: viewModel.session.formattedDuration
                    )

                    // Coverage toggle button
                    if viewModel.isScanning {
                        Button(action: { viewModel.toggleCoverageOverlay() }) {
                            Image(systemName: viewModel.showCoverageOverlay ? "map.fill" : "map")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel(viewModel.showCoverageOverlay ? "Skrýt mapu pokrytí" : "Zobrazit mapu pokrytí")
                    }

                    // Debug overlay toggle button
                    #if DEBUG
                    Button(action: { viewModel.showDebugOverlay.toggle() }) {
                        Image(systemName: viewModel.showDebugOverlay ? "text.bubble.fill" : "text.bubble")
                            .font(.title3)
                            .foregroundStyle(viewModel.showDebugOverlay ? .green : .white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(viewModel.showDebugOverlay ? "Skrýt debug log" : "Zobrazit debug log")
                    #endif

                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Nastavení")
                    .padding(.trailing)
                }
                .padding(.top, 8)

                // Memory pressure warning
                if viewModel.memoryPressure != .normal {
                    MemoryPressureWarning(level: viewModel.memoryPressure)
                        .padding(.top, 8)
                }

                Spacer()

                // Quality indicator (when scanning)
                if viewModel.isScanning {
                    ScanQualityIndicator(quality: viewModel.scanQuality)
                        .padding(.bottom, 8)

                    // ML Models indicator
                    if !viewModel.activeMLModels.isEmpty {
                        MLStatusIndicator(
                            models: viewModel.activeMLModels,
                            isProcessing: viewModel.isMLProcessing
                        )
                        .padding(.bottom, 20)
                    }
                }

                // Bottom controls
                ScanningControls(
                    isScanning: viewModel.isScanning,
                    canStart: viewModel.canStartScanning,
                    showMesh: viewModel.showMeshVisualization,
                    onStart: { viewModel.startScanning() },
                    onPause: { viewModel.pauseScanning() },
                    onStop: {
                        // Direct stop - show preview immediately
                        viewModel.stopScanning()
                    },
                    onStopLongPress: {
                        // Long press shows processing options
                        showStopOptions = true
                    },
                    onToggleMesh: { viewModel.toggleMeshVisualization() },
                    onClose: { dismiss() }
                )
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            viewModel.checkForResumableSessions()
            #if DEBUG
            DebugStreamService.shared.trackViewAppeared("ScanningView", details: ["mode": mode.rawValue])
            #endif
        }
        .onDisappear {
            viewModel.cleanup()
            #if DEBUG
            DebugStreamService.shared.trackViewDisappeared("ScanningView")
            #endif
        }
        .alert("Scanning Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .confirmationDialog("Dokončit skenování", isPresented: $showStopOptions) {
            Button("Uložit lokálně") {
                viewModel.stopScanning()
            }
            Button("Zpracovat s AI (cloud)") {
                Task {
                    await viewModel.stopAndProcess()
                }
            }
            Button("Pokračovat ve skenování", role: .cancel) {
                viewModel.resumeScanning()
            }
        } message: {
            Text("Jak chcete zpracovat sken?")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $viewModel.showPreview) {
            ModelPreviewPlaceholder(session: viewModel.session) { scanModel, session in
                onScanCompleted?(scanModel, session)
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $viewModel.showProcessing) {
            ProcessingProgressView(processingService: viewModel.processingService)
        }
        .sheet(isPresented: $viewModel.showResumeSheet) {
            ResumeSessionSheet(
                sessions: viewModel.resumableSessions,
                onResume: { sessionId in
                    Task {
                        await viewModel.resumeSession(sessionId: sessionId)
                    }
                },
                onNewScan: {
                    viewModel.startNewScan()
                },
                onDelete: { sessionId in
                    Task {
                        await viewModel.deleteSession(sessionId: sessionId)
                    }
                }
            )
        }
    }
}

// MARK: - Memory Pressure Warning

struct MemoryPressureWarning: View {
    let level: MemoryPressureLevel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: level == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(level == .critical ? .red : .orange)

            Text(level == .critical ? "Kritický nedostatek paměti" : "Varování: Nízká paměť")
                .font(.caption)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(level == .critical ? Color.red.opacity(0.8) : Color.orange.opacity(0.8), in: Capsule())
    }
}

// MARK: - ML Status Indicator

struct MLStatusIndicator: View {
    let models: [String]
    let isProcessing: Bool

    @State private var pulseAnimation = false

    var body: some View {
        HStack(spacing: 8) {
            // Activity indicator
            Image(systemName: "brain")
                .font(.caption)
                .foregroundStyle(.cyan)
                .opacity(isProcessing ? (pulseAnimation ? 1.0 : 0.5) : 0.8)

            // Model names
            Text(models.joined(separator: " • "))
                .font(.caption2)
                .foregroundStyle(.white)

            // Processing indicator
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.cyan)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}

// MARK: - AR View Container

struct ARViewContainer: UIViewRepresentable {
    let viewModel: ScanningViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR view
        arView.automaticallyConfigureSession = false
        arView.renderOptions = [
            .disableMotionBlur,
            .disableDepthOfField
        ]

        // Initialize AR session manager
        viewModel.setupARSession(with: arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Updates handled by viewModel
    }
}

// MARK: - Scanning Status Bar

struct ScanningStatusBar: View {
    let trackingState: String
    let worldMappingStatus: String
    let pointCount: Int
    let meshFaceCount: Int
    let fusedFrameCount: Int
    let scanDuration: String

    var body: some View {
        HStack {
            // Left side - tracking info
            VStack(alignment: .leading, spacing: 4) {
                Label(trackingState, systemImage: trackingStateIcon)
                    .font(.caption)
                Label(worldMappingStatus, systemImage: "map")
                    .font(.caption)
            }

            Spacer()

            // Center - duration
            VStack(spacing: 2) {
                Text(scanDuration)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)

                if fusedFrameCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.caption2)
                        Text("\(fusedFrameCount) AI")
                            .font(.caption2)
                    }
                    .foregroundStyle(.cyan)
                }
            }

            Spacer()

            // Right side - statistics
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatNumber(pointCount) + " pts")
                    .font(.caption)
                Text(formatNumber(meshFaceCount) + " faces")
                    .font(.caption)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.leading)
    }

    private var trackingStateIcon: String {
        switch trackingState {
        case "Normal": return "checkmark.circle.fill"
        case _ where trackingState.contains("Limited"): return "exclamationmark.triangle.fill"
        default: return "xmark.circle.fill"
        }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.0fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
}

// MARK: - Scanning Controls

struct ScanningControls: View {
    let isScanning: Bool
    let canStart: Bool
    let showMesh: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    var onStopLongPress: (() -> Void)? = nil
    let onToggleMesh: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 40) {
            // Mesh toggle button
            Button(action: onToggleMesh) {
                Image(systemName: showMesh ? "cube.fill" : "cube")
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel(showMesh ? "Skrýt 3D mesh" : "Zobrazit 3D mesh")

            // Main control button
            Button(action: {
                if isScanning {
                    onPause()
                } else {
                    onStart()
                }
            }) {
                Image(systemName: isScanning ? "pause.fill" : "record.circle")
                    .font(.largeTitle)
                    .foregroundStyle(isScanning ? .white : .red)
                    .frame(width: 70, height: 70)
                    .background(isScanning ? Color.orange : Color.white.opacity(0.2))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                    )
            }
            .disabled(!canStart && !isScanning)
            .opacity((!canStart && !isScanning) ? 0.5 : 1)
            .accessibilityLabel(isScanning ? "Pozastavit skenování" : "Zahájit skenování")

            // Stop/Close button
            if isScanning {
                // Stop button with tap and long press gestures
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .foregroundStyle(.white)
                    .onTapGesture {
                        onStop()
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        onStopLongPress?()
                    }
                    .accessibilityLabel("Ukončit skenování")
                    .accessibilityHint("Klepnutí ukončí sken, podržení zobrazí možnosti zpracování")
            } else {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Zavřít")
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Scan Quality Indicator

struct ScanQualityIndicator: View {
    let quality: ScanQuality

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < quality.level ? quality.color : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 16 + CGFloat(index * 4))
            }

            Text(quality.displayName)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Model Preview Placeholder

struct ModelPreviewPlaceholder: View {
    let session: ScanSession
    let onSave: (ScanModel, ScanSession) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scanName: String

    init(session: ScanSession, onSave: @escaping (ScanModel, ScanSession) -> Void) {
        self.session = session
        self.onSave = onSave
        self._scanName = State(initialValue: session.name)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.gradient)

                Text("Sken dokončen")
                    .font(.title)
                    .fontWeight(.bold)

                // Editable scan name
                TextField("Název skenu", text: $scanName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                VStack(spacing: 8) {
                    StatRow(label: "Vrcholy", value: "\(session.vertexCount.formatted())")
                    StatRow(label: "Plochy", value: "\(session.faceCount.formatted())")
                    StatRow(label: "Doba skenu", value: session.formattedDuration)
                    StatRow(label: "Plocha", value: String(format: "%.2f m²", session.areaScanned))
                    StatRow(label: "Body", value: "\(session.pointCloud?.pointCount ?? 0)")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()

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
            .navigationTitle("Náhled skenu")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func saveAndDismiss() {
        // Update session name
        session.name = scanName.isEmpty ? "Sken \(Date().formatted(date: .abbreviated, time: .shortened))" : scanName

        // Convert ScanSession to ScanModel
        let scanModel = ScanModel(
            id: session.id.uuidString,
            name: session.name,
            createdAt: session.createdAt,
            thumbnail: nil, // TODO: Generate thumbnail from point cloud/mesh
            pointCount: session.pointCloud?.pointCount ?? session.vertexCount,
            faceCount: session.faceCount,
            fileSize: Int64(session.vertexCount * 12 + session.faceCount * 12), // Rough estimate
            isProcessed: false,
            localURL: nil // TODO: Save to disk and store URL
        )

        onSave(scanModel, session)
        dismiss()
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
    ScanningView(mode: .exterior)
}
