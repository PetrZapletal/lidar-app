import SwiftUI

// MARK: - Unified Scanning View

/// Generic scanning view that works with any scanning mode conforming to ScanningModeProtocol
/// Provides consistent UI structure while allowing mode-specific customization
struct UnifiedScanningView<Mode: ScanningModeProtocol>: View {
    @State private var mode: Mode
    @State private var showResults = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var onScanCompleted: ((ScanModel, ScanSession) -> Void)?

    init(mode: Mode, onScanCompleted: ((ScanModel, ScanSession) -> Void)? = nil) {
        self._mode = State(initialValue: mode)
        self.onScanCompleted = onScanCompleted
    }

    var body: some View {
        ZStack {
            // Mode-specific content (AR view, camera feed, etc.)
            mode.makeMiddleContentView()
                .ignoresSafeArea()

            // Overlay UI
            VStack(spacing: 0) {
                // Top bar
                SharedTopBar(
                    status: mode.scanStatus,
                    statusSubtitle: mode.statusSubtitle,
                    onClose: {
                        mode.cancelScanning()
                        dismiss()
                    }
                ) {
                    mode.makeTopBarRightContent()
                }

                Spacer()

                // Mode-specific statistics
                mode.makeStatsView()

                // Bottom control bar
                SharedControlBar(
                    captureState: mode.captureButtonState,
                    onCaptureTap: {
                        handleCaptureTap()
                    }
                ) {
                    mode.makeLeftAccessory()
                } rightContent: {
                    mode.makeRightAccessory()
                }
            }
        }
        .onAppear {
            Task {
                await mode.startScanning()
            }
        }
        .onDisappear {
            mode.cancelScanning()
        }
        .onChange(of: scenePhase) { _, newPhase in
            mode.handleScenePhaseChange(to: newPhase)
        }
        .fullScreenCover(isPresented: $showResults) {
            mode.makeResultsView(
                onSave: { scanModel, session in
                    onScanCompleted?(scanModel, session)
                    showResults = false
                    dismiss()
                },
                onDismiss: {
                    showResults = false
                    dismiss()
                }
            )
        }
        .onChange(of: mode.hasResults) { _, hasResults in
            if hasResults {
                showResults = true
            }
        }
    }

    private func handleCaptureTap() {
        if mode.isScanning {
            Task {
                await mode.stopScanning()
            }
        }
    }
}

// MARK: - LiDAR Specialized Unified View

/// Specialized unified view for LiDAR mode with custom top bar
/// LiDAR mode has a more detailed status bar, so it needs a custom implementation
struct LiDARUnifiedScanningView: View {
    @State private var mode: LiDARScanningModeAdapter
    @State private var showResults = false
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var onScanCompleted: ((ScanModel, ScanSession) -> Void)?

    init(scanMode: ScanMode = .exterior, onScanCompleted: ((ScanModel, ScanSession) -> Void)? = nil) {
        self._mode = State(initialValue: LiDARScanningModeAdapter(mode: scanMode))
        self.onScanCompleted = onScanCompleted
    }

    var body: some View {
        ZStack {
            // LiDAR-specific content
            mode.makeMiddleContentView()
                .ignoresSafeArea()

            // Overlay UI
            VStack(spacing: 0) {
                // LiDAR-specific top bar with detailed status
                HStack {
                    ScanningStatusBar(
                        trackingState: mode.trackingStateText,
                        worldMappingStatus: mode.worldMappingStatusText,
                        pointCount: mode.pointCount,
                        meshFaceCount: mode.meshFaceCount,
                        fusedFrameCount: mode.fusedFrameCount,
                        scanDuration: mode.scanDuration
                    )

                    mode.makeTopBarRightContent()

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
                if mode.memoryPressure != .normal {
                    MemoryPressureWarning(level: mode.memoryPressure)
                        .padding(.top, 8)
                }

                Spacer()

                // Statistics (quality indicator, ML models)
                mode.makeStatsView()

                // Bottom control bar - LiDAR has pause/resume behavior
                LiDARControlBar(
                    mode: mode,
                    onStop: {
                        Task {
                            await mode.stopScanning()
                        }
                    },
                    onClose: {
                        mode.cancelScanning()
                        dismiss()
                    }
                )
            }

            // Mock mode warning banner
            if mode.isMockMode {
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
                    .padding(.top, 100)

                    Spacer()
                }
            }
        }
        .onAppear {
            Task {
                await mode.startScanning()
            }
        }
        .onDisappear {
            mode.cancelScanning()
        }
        .onChange(of: scenePhase) { _, newPhase in
            mode.handleScenePhaseChange(to: newPhase)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showResults) {
            mode.makeResultsView(
                onSave: { scanModel, session in
                    onScanCompleted?(scanModel, session)
                    showResults = false
                    dismiss()
                },
                onDismiss: {
                    showResults = false
                    dismiss()
                }
            )
        }
        .onChange(of: mode.hasResults) { _, hasResults in
            if hasResults {
                showResults = true
            }
        }
    }
}

// MARK: - LiDAR Control Bar

/// Custom control bar for LiDAR mode with state-dependent layout:
/// - Ready: Center = record (start), no side buttons
/// - Scanning: Left = mesh, Center = finish (stop), Right = pause
/// - Paused: Left = mesh, Center = resume, Right = finish (stop)
struct LiDARControlBar: View {
    let mode: LiDARScanningModeAdapter
    let onStop: () -> Void
    let onClose: () -> Void
    @State private var showMesh = false

    private var isReady: Bool {
        !mode.isScanning && !mode.isPaused
    }

    var body: some View {
        HStack(spacing: 30) {
            if isReady {
                // MARK: Ready State - only center start button
                Spacer()
                    .frame(width: 50)

                readyButton

                Spacer()
                    .frame(width: 50)
            } else if mode.isScanning {
                // MARK: Scanning State
                // Left: Mesh toggle
                meshToggleButton

                // Center: Finish scan (primary action)
                finishButton

                // Right: Pause
                pauseButton
            } else {
                // MARK: Paused State
                // Left: Mesh toggle
                meshToggleButton

                // Center: Resume (primary action)
                resumeButton

                // Right: Finish/End scan
                endButton
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    // MARK: - Ready State Button

    /// Large red record button to start scanning
    private var readyButton: some View {
        Button(action: {
            Task {
                await mode.startScanning()
            }
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)

                    if mode.canStartScanning {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 64, height: 64)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 64, height: 64)
                    }
                }
            }
        }
        .disabled(!mode.canStartScanning)
        .opacity(mode.canStartScanning ? 1 : 0.5)
        .accessibilityLabel("Zahájit skenování")
    }

    // MARK: - Scanning State Buttons

    /// Large red stop button - primary action during scanning
    private var finishButton: some View {
        Button(action: onStop) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)

                    Image(systemName: "stop.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                Text("Dokončit")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .accessibilityLabel("Dokončit skenování")
    }

    /// Orange pause button - side action during scanning
    private var pauseButton: some View {
        Button(action: {
            mode.pauseScanning()
        }) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 50, height: 50)

                    Image(systemName: "pause.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
                Text("Pauza")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 50)
        .accessibilityLabel("Pozastavit skenování")
    }

    // MARK: - Paused State Buttons

    /// Large green resume button - primary action when paused
    private var resumeButton: some View {
        Button(action: {
            mode.resumeScanning()
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 70, height: 70)

                    Image(systemName: "play.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                Text("Pokračovat")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .accessibilityLabel("Pokračovat ve skenování")
    }

    /// Small red stop button - secondary action when paused
    private var endButton: some View {
        Button(action: onStop) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 50, height: 50)

                    Image(systemName: "stop.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
                Text("Ukončit")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 50)
        .accessibilityLabel("Ukončit skenování")
    }

    // MARK: - Shared Buttons

    /// Mesh visualization toggle - shown during scanning and paused states
    private var meshToggleButton: some View {
        Button(action: {
            showMesh.toggle()
            mode.toggleMeshVisualization()
        }) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(showMesh ? Color.white.opacity(0.3) : Color.white.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: showMesh ? "cube.fill" : "cube")
                        .font(.system(size: 20))
                        .foregroundStyle(showMesh ? .white : .white.opacity(0.7))
                }
                Text("Mřížka")
                    .font(.system(size: 10))
                    .foregroundStyle(showMesh ? .white.opacity(0.9) : .white.opacity(0.7))
            }
        }
        .frame(width: 50)
        .accessibilityLabel(showMesh ? "Skrýt mřížku" : "Zobrazit mřížku")
    }
}

// MARK: - Previews

#Preview("LiDAR Mode") {
    LiDARUnifiedScanningView()
}

#Preview("RoomPlan Mode") {
    UnifiedScanningView(mode: RoomPlanScanningModeAdapter())
}

#Preview("Object Capture Mode") {
    UnifiedScanningView(mode: ObjectCaptureScanningModeAdapter())
}
