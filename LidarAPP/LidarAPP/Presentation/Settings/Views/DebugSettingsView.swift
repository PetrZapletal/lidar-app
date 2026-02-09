import SwiftUI

/// Debug panel - detailní nastavení pro vývojáře
struct DebugSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let services: ServiceContainer
    @State private var showLogsView = false
    @State private var showClearLogsConfirmation = false
    @State private var showExportedLogsShare = false
    @State private var exportedLogsURL: URL?

    var body: some View {
        List {
            streamSection
            loggingSection
            rawDataSection
            textureSection
            logsSection
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Vymazat logy", isPresented: $showClearLogsConfirmation) {
            Button("Zrušit", role: .cancel) { }
            Button("Vymazat", role: .destructive) {
                viewModel.clearLogs()
            }
        } message: {
            Text("Všechny uložené logy budou smazány.")
        }
        .sheet(isPresented: $showExportedLogsShare) {
            if let url = exportedLogsURL {
                DebugShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showLogsView) {
            RecentLogsView(viewModel: viewModel)
        }
        .accessibilityIdentifier("debugSettings.view")
    }

    // MARK: - Stream Section

    private var streamSection: some View {
        Section {
            Toggle("Debug stream", isOn: $viewModel.debugStreamEnabled)
                .accessibilityIdentifier("debugSettings.streamToggle")
        } header: {
            Text("Debug Stream")
        } footer: {
            Text("Streamuje debug informace na vzdálený server pro analýzu v reálném čase.")
        }
    }

    // MARK: - Logging Section

    private var loggingSection: some View {
        Section {
            Toggle("Podrobné logování", isOn: $viewModel.verboseLogging)
                .accessibilityIdentifier("debugSettings.verboseLoggingToggle")

            Toggle("Performance overlay", isOn: $viewModel.showPerformanceOverlay)
                .accessibilityIdentifier("debugSettings.performanceOverlayToggle")
        } header: {
            Text("Logování")
        } footer: {
            Text("Podrobné logování zvyšuje velikost log bufferu a může ovlivnit výkon.")
        }
    }

    // MARK: - Raw Data Section

    private var rawDataSection: some View {
        Section {
            Toggle("Raw data režim", isOn: $viewModel.rawDataModeEnabled)
                .accessibilityIdentifier("debugSettings.rawDataToggle")
        } header: {
            Text("Raw Data Pipeline")
        } footer: {
            Text("Odesílá surová data přímo na server bez lokálního zpracování. Užitečné pro vývoj a ladění.")
        }
    }

    // MARK: - Texture Section

    private var textureSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Kvalita textur")
                    Spacer()
                    Text("\(Int(viewModel.textureQuality * 100))%")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Slider(value: $viewModel.textureQuality, in: 0.1...1.0, step: 0.05)
                    .accessibilityIdentifier("debugSettings.textureQualitySlider")
            }

            Stepper(
                "Max. snímků textur: \(viewModel.maxTextureFrames)",
                value: $viewModel.maxTextureFrames,
                in: 50...2000,
                step: 50
            )
            .accessibilityIdentifier("debugSettings.maxTextureFramesStepper")
        } header: {
            Text("Textury")
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        Section {
            Button {
                showLogsView = true
            } label: {
                HStack {
                    Label("Zobrazit nedávné logy", systemImage: "doc.text.magnifyingglass")
                    Spacer()
                    Text("\(services.logger.logCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
            .accessibilityIdentifier("debugSettings.viewLogsButton")

            Button {
                if let url = viewModel.exportLogs() {
                    exportedLogsURL = url
                    showExportedLogsShare = true
                }
            } label: {
                Label("Exportovat logy", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("debugSettings.exportLogsButton")

            Button(role: .destructive) {
                showClearLogsConfirmation = true
            } label: {
                Label("Vymazat logy", systemImage: "trash")
            }
            .accessibilityIdentifier("debugSettings.clearLogsButton")
        } header: {
            Text("Logy")
        }
    }
}

// MARK: - Recent Logs View

private struct RecentLogsView: View {
    let viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.recentLogs.isEmpty {
                    ContentUnavailableView {
                        Label("Žádné logy", systemImage: "doc.text")
                    } description: {
                        Text("Zatím nebyly zaznamenány žádné logy.")
                    }
                } else {
                    ForEach(viewModel.recentLogs) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.level.emoji)
                                    .font(.caption)
                                Text(entry.level.rawValue.uppercased())
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(colorForLevel(entry.level))

                                if let category = entry.category {
                                    Text("[\(category)]")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(entry.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(3)

                            Text("\(URL(fileURLWithPath: entry.file).lastPathComponent):\(entry.line)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Nedávné logy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hotovo") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Share Sheet

private struct DebugShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
