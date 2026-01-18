import SwiftUI

/// View for displaying scan processing progress
struct ProcessingProgressView: View {
    @ObservedObject var processingService: ScanProcessingService

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            headerView

            Spacer()

            // Progress indicator
            progressView

            // Stats
            if let stats = processingService.processingStats {
                statsView(stats)
            }

            Spacer()

            // Action buttons
            actionButtons
        }
        .padding(24)
        .background(Color(.systemBackground))
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            Text(stateTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(stateSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var stateTitle: String {
        switch processingService.state {
        case .idle:
            return "Připraveno"
        case .scanning:
            return "Skenování"
        case .processing(let stage, _):
            return stage.displayName
        case .uploading:
            return "Nahrávání"
        case .serverProcessing(let stage, _):
            return serverStageDisplayName(stage)
        case .downloading:
            return "Stahování"
        case .completed:
            return "Dokončeno"
        case .failed:
            return "Chyba"
        }
    }

    private var stateSubtitle: String {
        switch processingService.state {
        case .idle:
            return "Začněte skenovat"
        case .scanning:
            return "Pohybujte zařízením pro zachycení prostoru"
        case .processing:
            return "Zpracování na zařízení"
        case .uploading:
            return "Odesílání dat na server"
        case .serverProcessing:
            return "AI zpracování v cloudu"
        case .downloading:
            return "Stahování výsledku"
        case .completed:
            return "Model je připraven"
        case .failed(let error):
            return error
        }
    }

    private func serverStageDisplayName(_ stage: String) -> String {
        switch stage {
        case "preprocessing":
            return "Předzpracování"
        case "gaussian_splatting":
            return "3D Gaussian Splatting"
        case "mesh_extraction":
            return "Extrakce mesh"
        case "texture_baking":
            return "Texturování"
        case "export":
            return "Export"
        default:
            return stage.capitalized
        }
    }

    // MARK: - Progress View

    @ViewBuilder
    private var progressView: some View {
        switch processingService.state {
        case .idle:
            idleView

        case .scanning(let progress):
            circularProgress(progress: progress, color: .blue, icon: "camera.viewfinder")

        case .processing(_, let progress):
            circularProgress(progress: progress, color: .purple, icon: "cpu")

        case .uploading(let progress):
            circularProgress(progress: progress, color: .orange, icon: "arrow.up.circle")

        case .serverProcessing(_, let progress):
            circularProgress(progress: progress, color: .green, icon: "cloud")

        case .downloading(let progress):
            circularProgress(progress: progress, color: .cyan, icon: "arrow.down.circle")

        case .completed:
            completedView

        case .failed:
            failedView
        }
    }

    private var idleView: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                .frame(width: 160, height: 160)

            Image(systemName: "viewfinder")
                .font(.system(size: 48))
                .foregroundColor(.gray)
        }
    }

    private func circularProgress(progress: Float, color: Color, icon: String) -> some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 8)
                .frame(width: 160, height: 160)

            // Progress circle
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)

            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)

                Text("\(Int(progress * 100))%")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
    }

    private var completedView: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.1))
                .frame(width: 160, height: 160)

            Circle()
                .stroke(Color.green, lineWidth: 8)
                .frame(width: 160, height: 160)

            Image(systemName: "checkmark")
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(.green)
        }
    }

    private var failedView: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.1))
                .frame(width: 160, height: 160)

            Circle()
                .stroke(Color.red, lineWidth: 8)
                .frame(width: 160, height: 160)

            Image(systemName: "xmark")
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(.red)
        }
    }

    // MARK: - Stats View

    private func statsView(_ stats: ScanProcessingService.ProcessingStats) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 32) {
                statItem(
                    icon: "point.3.connected.trianglepath.dotted",
                    value: formatNumber(stats.pointCount),
                    label: "Bodů"
                )

                statItem(
                    icon: "photo.stack",
                    value: "\(stats.fusedFrameCount)",
                    label: "Snímků"
                )
            }

            if stats.totalBytes > 0 {
                HStack(spacing: 32) {
                    statItem(
                        icon: "arrow.up.circle",
                        value: formatBytes(stats.uploadedBytes),
                        label: "Nahráno"
                    )

                    statItem(
                        icon: "timer",
                        value: formatDuration(stats.elapsedTime),
                        label: "Čas"
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.secondary)

            Text(value)
                .font(.headline)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 80)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        switch processingService.state {
        case .idle:
            EmptyView()

        case .completed:
            HStack(spacing: 16) {
                Button("Zavřít") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Zobrazit model") {
                    // Navigate to model preview
                }
                .buttonStyle(.borderedProminent)
            }

        case .failed:
            HStack(spacing: 16) {
                Button("Zavřít") {
                    processingService.cancel()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Zkusit znovu") {
                    // Retry processing
                }
                .buttonStyle(.borderedProminent)
            }

        default:
            Button("Zrušit") {
                processingService.cancel()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
    }

    // MARK: - Formatting Helpers

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.0fK", Double(number) / 1_000)
        }
        return "\(number)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Processing Stage Timeline

struct ProcessingStageTimeline: View {
    let stages: [ProcessingStageInfo]
    let currentStage: String?

    struct ProcessingStageInfo: Identifiable {
        let id: String
        let name: String
        let progress: Float
        let isComplete: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                HStack(spacing: 12) {
                    // Indicator
                    ZStack {
                        Circle()
                            .fill(stageColor(for: stage))
                            .frame(width: 24, height: 24)

                        if stage.isComplete {
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        } else if stage.id == currentStage {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 12, height: 12)
                        }
                    }

                    // Stage info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.name)
                            .font(.subheadline)
                            .fontWeight(stage.id == currentStage ? .semibold : .regular)
                            .foregroundColor(stage.isComplete || stage.id == currentStage ? .primary : .secondary)

                        if stage.id == currentStage && stage.progress > 0 {
                            ProgressView(value: stage.progress)
                                .tint(.blue)
                        }
                    }

                    Spacer()
                }

                // Connector line
                if index < stages.count - 1 {
                    Rectangle()
                        .fill(stage.isComplete ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 2, height: 20)
                        .padding(.leading, 11)
                }
            }
        }
        .padding()
    }

    private func stageColor(for stage: ProcessingStageInfo) -> Color {
        if stage.isComplete {
            return .green
        } else if stage.id == currentStage {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }
}

#Preview {
    ProcessingProgressView(processingService: ScanProcessingService())
}
