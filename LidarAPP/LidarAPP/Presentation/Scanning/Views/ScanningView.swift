import SwiftUI
import RealityKit

/// Main scanning interface view
struct ScanningView: View {
    @State private var viewModel = ScanningViewModel()
    @State private var showSettings = false
    @State private var showStopOptions = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // AR View (full screen)
            ARViewContainer(viewModel: viewModel)
                .ignoresSafeArea()

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

                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.trailing)
                }
                .padding(.top, 8)

                Spacer()

                // Quality indicator (when scanning)
                if viewModel.isScanning {
                    ScanQualityIndicator(quality: viewModel.scanQuality)
                        .padding(.bottom, 20)
                }

                // Bottom controls
                ScanningControls(
                    isScanning: viewModel.isScanning,
                    canStart: viewModel.canStartScanning,
                    showMesh: viewModel.showMeshVisualization,
                    onStart: { viewModel.startScanning() },
                    onPause: { viewModel.pauseScanning() },
                    onStop: { showStopOptions = true },
                    onToggleMesh: { viewModel.toggleMeshVisualization() },
                    onClose: { dismiss() }
                )
                .padding(.bottom, 30)
            }
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
            ModelPreviewPlaceholder(session: viewModel.session)
        }
        .fullScreenCover(isPresented: $viewModel.showProcessing) {
            ProcessingProgressView(processingService: viewModel.processingService)
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

            // Stop/Close button
            Button(action: {
                if isScanning {
                    onStop()
                } else {
                    onClose()
                }
            }) {
                Image(systemName: isScanning ? "stop.fill" : "xmark")
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.gradient)

                Text("Scan Complete")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(spacing: 8) {
                    StatRow(label: "Vertices", value: "\(session.vertexCount.formatted())")
                    StatRow(label: "Faces", value: "\(session.faceCount.formatted())")
                    StatRow(label: "Duration", value: session.formattedDuration)
                    StatRow(label: "Area", value: String(format: "%.2f m²", session.areaScanned))
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()

                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .navigationTitle(session.name)
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
    ScanningView()
}
