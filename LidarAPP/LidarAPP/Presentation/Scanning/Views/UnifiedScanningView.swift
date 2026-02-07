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

/// Custom control bar for LiDAR mode with pause/resume and mesh toggle
struct LiDARControlBar: View {
    let mode: LiDARScanningModeAdapter
    let onStop: () -> Void
    let onClose: () -> Void
    @State private var showMesh = false

    var body: some View {
        HStack(spacing: 40) {
            // Mesh toggle button
            ControlAccessoryButton(
                icon: showMesh ? "cube.fill" : "cube",
                label: "Mesh",
                action: {
                    showMesh.toggle()
                    mode.toggleMeshVisualization()
                },
                isActive: showMesh
            )
            .frame(width: 50)

            // Main control button - pause/resume
            Button(action: {
                if mode.isScanning {
                    mode.pauseScanning()
                } else if mode.canStartScanning {
                    Task {
                        await mode.startScanning()
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)

                    if mode.isScanning {
                        // Pause icon when scanning
                        Image(systemName: "pause.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .frame(width: 65, height: 65)
                            .background(Color.orange)
                            .clipShape(Circle())
                    } else if mode.canStartScanning {
                        // Record icon when ready
                        Circle()
                            .fill(Color.red)
                            .frame(width: 60, height: 60)
                    } else {
                        // Disabled state
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 60, height: 60)
                    }
                }
            }
            .disabled(!mode.canStartScanning && !mode.isScanning)
            .opacity((!mode.canStartScanning && !mode.isScanning) ? 0.5 : 1)
            .accessibilityLabel(mode.isScanning ? "Pozastavit skenování" : "Zahájit skenování")

            // Stop/Close button
            if mode.isScanning {
                ControlAccessoryButton(
                    icon: "stop.fill",
                    label: "Stop",
                    action: onStop
                )
                .frame(width: 50)
            } else {
                ControlAccessoryButton(
                    icon: "xmark",
                    label: "Zavřít",
                    action: onClose
                )
                .frame(width: 50)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
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
