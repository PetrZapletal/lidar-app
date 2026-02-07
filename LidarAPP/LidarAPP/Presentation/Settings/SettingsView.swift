import SwiftUI
import UIKit

/// Main settings view
struct SettingsView: View {
    @AppStorage("backendURL") private var backendURL = "https://api.lidarscanner.app"
    @AppStorage("enableDepthFusion") private var enableDepthFusion = true
    @AppStorage("targetPointCount") private var targetPointCount = 500_000
    @AppStorage("meshResolution") private var meshResolution = "high"
    @AppStorage("textureResolution") private var textureResolution = 4096
    @AppStorage("autoUpload") private var autoUpload = true
    @AppStorage("outputFormats") private var outputFormatsString = "usdz,gltf"
    @AppStorage("MockModeEnabled") private var mockModeEnabled = MockDataProvider.isSimulator

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                developerSection
                debugUploadSection
                #if DEBUG
                debugStreamSection
                #endif
                backendSection
                processingSection
                qualitySection
                exportSection
                diagnosticsSection
                aboutSection
            }
            .navigationTitle("Nastavení")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hotovo") {
                        dismiss()
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.doneButton)
                }
            }
        }
    }

    // MARK: - Developer Section

    private var developerSection: some View {
        Section {
            Toggle("Mock Mode", isOn: $mockModeEnabled)
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.mockModeToggle)

            if mockModeEnabled {
                HStack {
                    Text("Status")
                    Spacer()
                    Label("Aktivní", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.orange)
                }

                NavigationLink {
                    MockDataPreviewView()
                } label: {
                    Text("Preview mock dat")
                }
            }

            HStack {
                Text("Simulátor")
                Spacer()
                Text(MockDataProvider.isSimulator ? "Ano" : "Ne")
                    .foregroundColor(.secondary)
            }
        } header: {
            Label("Vývojář", systemImage: "hammer.fill")
        } footer: {
            Text("Mock mode umožňuje testování aplikace bez LiDAR senzoru. Automaticky aktivní na simulátoru.")
        }
    }

    // MARK: - Debug Upload Section

    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?
    @State private var connectionTestSuccess = false

    private var debugSettings: DebugSettings { DebugSettings.shared }

    private var debugUploadSection: some View {
        Section {
            Toggle("Raw Data Mode", isOn: Binding(
                get: { debugSettings.rawDataModeEnabled },
                set: { debugSettings.rawDataModeEnabled = $0 }
            ))
            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.rawDataModeToggle)

            if debugSettings.rawDataModeEnabled {
                HStack {
                    Text("Tailscale IP")
                    Spacer()
                    TextField("100.x.x.x", text: Binding(
                        get: { debugSettings.tailscaleIP },
                        set: { debugSettings.tailscaleIP = $0 }
                    ))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 150)
                }

                Stepper("Port: \(debugSettings.serverPort)", value: Binding(
                    get: { debugSettings.serverPort },
                    set: { debugSettings.serverPort = $0 }
                ), in: 8000...9999)

                Toggle("Incluye Depth Maps", isOn: Binding(
                    get: { debugSettings.includeDepthMaps },
                    set: { debugSettings.includeDepthMaps = $0 }
                ))

                Button(action: testDebugConnection) {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text("Test Connection")
                        Spacer()
                        if let result = connectionTestResult {
                            Image(systemName: connectionTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(connectionTestSuccess ? .green : .red)
                        }
                    }
                }
                .disabled(isTestingConnection)
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.testConnectionButton)

                if let result = connectionTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(connectionTestSuccess ? .green : .red)
                }

                // Show current URL
                if let url = debugSettings.rawDataBaseURL {
                    HStack {
                        Text("URL")
                        Spacer()
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Always visible - Reset button and current settings info
            HStack {
                Text("Aktuální URL")
                Spacer()
                Text("https://\(debugSettings.tailscaleIP):\(debugSettings.serverPort)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(role: .destructive) {
                debugSettings.resetToDefaults()
                connectionTestResult = nil
            } label: {
                HStack {
                    Spacer()
                    Text("Obnovit výchozí nastavení")
                    Spacer()
                }
            }
        } header: {
            Label("Debug Upload", systemImage: "arrow.up.circle")
        } footer: {
            Text("Raw Data Mode odesílá surová data přímo na backend místo lokálního zpracování. Výchozí: https://100.96.188.18:8444")
        }
    }

    private func testDebugConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        Task {
            let (success, message, latency) = await debugSettings.testConnection()
            await MainActor.run {
                connectionTestSuccess = success
                if let lat = latency {
                    connectionTestResult = "\(message) (\(String(format: "%.0f", lat))ms)"
                } else {
                    connectionTestResult = message
                }
                isTestingConnection = false
            }
        }
    }

    // MARK: - Debug Stream Section

    #if DEBUG
    private var debugStreamSection: some View {
        Section {
            Toggle("Enable Debug Stream", isOn: Binding(
                get: { debugSettings.debugStreamEnabled },
                set: { debugSettings.debugStreamEnabled = $0 }
            ))

            if debugSettings.debugStreamEnabled {
                HStack {
                    Text("Server IP")
                    Spacer()
                    TextField("100.x.x.x", text: Binding(
                        get: { debugSettings.debugStreamServerIP },
                        set: { debugSettings.debugStreamServerIP = $0 }
                    ))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 150)
                }

                Picker("Mode", selection: Binding(
                    get: { debugSettings.debugStreamMode },
                    set: { debugSettings.debugStreamMode = $0 }
                )) {
                    Text("Real-time (WebSocket)").tag("realtime")
                    Text("Batch (HTTP)").tag("batch")
                }

                if debugSettings.debugStreamMode == "batch" {
                    Stepper("Interval: \(Int(debugSettings.batchInterval))s", value: Binding(
                        get: { debugSettings.batchInterval },
                        set: { debugSettings.batchInterval = $0 }
                    ), in: 1...30)
                }

                NavigationLink {
                    DebugCategoriesView()
                } label: {
                    HStack {
                        Text("Categories")
                        Spacer()
                        Text("\(debugSettings.enabledCategories.count) enabled")
                            .foregroundColor(.secondary)
                    }
                }

                // Stream status
                HStack {
                    Text("Status")
                    Spacer()
                    Circle()
                        .fill(DebugStreamService.shared.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(DebugStreamService.shared.isConnected ? "Connected" : "Disconnected")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Events sent")
                    Spacer()
                    Text("\(DebugStreamService.shared.eventsSent)")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Label("Debug Stream", systemImage: "waveform")
        } footer: {
            Text("Streamuje diagnostická data v reálném čase na debug server. Pouze pro development builds.")
        }
    }
    #endif

    // MARK: - Backend Section

    private var backendSection: some View {
        Section {
            TextField("URL serveru", text: $backendURL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .textContentType(.URL)

            Toggle("Automatický upload", isOn: $autoUpload)

            NavigationLink {
                BackendStatusView(url: backendURL)
            } label: {
                HStack {
                    Text("Stav serveru")
                    Spacer()
                    Image(systemName: "circle.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                }
            }
        } header: {
            Text("Backend")
        } footer: {
            Text("URL serveru pro AI zpracování skenů.")
        }
    }

    // MARK: - Processing Section

    private var processingSection: some View {
        Section {
            Toggle("Depth Fusion", isOn: $enableDepthFusion)
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.depthFusionToggle)

            Stepper("Cílový počet bodů: \(targetPointCount / 1000)K", value: $targetPointCount, in: 100_000...2_000_000, step: 100_000)
        } header: {
            Text("Zpracování")
        } footer: {
            Text("Depth Fusion kombinuje LiDAR data s AI hloubkovou mapou pro vyšší rozlišení.")
        }
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        Section {
            Picker("Rozlišení mesh", selection: $meshResolution) {
                Text("Nízké").tag("low")
                Text("Střední").tag("medium")
                Text("Vysoké").tag("high")
            }

            Picker("Rozlišení textur", selection: $textureResolution) {
                Text("2K (2048)").tag(2048)
                Text("4K (4096)").tag(4096)
                Text("8K (8192)").tag(8192)
            }
        } header: {
            Text("Kvalita")
        } footer: {
            Text("Vyšší kvalita vyžaduje více času na zpracování.")
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            NavigationLink {
                ExportFormatsView(selectedFormats: $outputFormatsString)
            } label: {
                HStack {
                    Text("Výstupní formáty")
                    Spacer()
                    Text(formatDisplayText)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Export")
        }
    }

    private var formatDisplayText: String {
        let formats = outputFormatsString.split(separator: ",").map(String.init)
        return formats.map { $0.uppercased() }.joined(separator: ", ")
    }

    // MARK: - Diagnostics Section

    @State private var diagnosticsCount = 0
    @State private var showDiagnosticsExport = false
    @State private var exportedFileURL: URL?

    private var diagnosticsSection: some View {
        Section {
            HStack {
                Text("Crash reporty")
                Spacer()
                Text("\(CrashReporter.shared.getDiagnostics().count)")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Metriky")
                Spacer()
                Text("\(CrashReporter.shared.getMetrics().count)")
                    .foregroundColor(.secondary)
            }

            Button("Exportovat diagnostiku") {
                exportedFileURL = CrashReporter.shared.saveDiagnosticsToFile()
                if exportedFileURL != nil {
                    showDiagnosticsExport = true
                }
            }

            NavigationLink {
                DiagnosticsDetailView()
            } label: {
                Text("Crash detaily")
            }

            NavigationLink {
                DiagnosticsView()
            } label: {
                Label("Testování komponent", systemImage: "checklist")
            }
        } header: {
            Label("Diagnostika", systemImage: "stethoscope")
        } footer: {
            Text("Testování komponent umožňuje rychlou kontrolu funkčnosti všech částí aplikace.")
        }
        .sheet(isPresented: $showDiagnosticsExport) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Verze")
                Spacer()
                Text(Bundle.main.appVersion)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.buildNumber)
                    .foregroundColor(.secondary)
            }

            Link(destination: URL(string: "https://lidarscanner.app/privacy")!) {
                Text("Zásady ochrany osobních údajů")
            }

            Link(destination: URL(string: "https://lidarscanner.app/terms")!) {
                Text("Podmínky použití")
            }
        } header: {
            Text("O aplikaci")
        }
    }
}

// MARK: - Backend Status View

struct BackendStatusView: View {
    let url: String

    @State private var isConnected = false
    @State private var isChecking = true
    @State private var serverVersion: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Text("URL")
                    Spacer()
                    Text(url)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Stav")
                    Spacer()
                    if isChecking {
                        ProgressView()
                    } else if isConnected {
                        Label("Připojeno", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Odpojeno", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }

                if let version = serverVersion {
                    HStack {
                        Text("Verze serveru")
                        Spacer()
                        Text(version)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            Section {
                Button("Znovu otestovat připojení") {
                    Task {
                        await checkConnection()
                    }
                }
            }
        }
        .navigationTitle("Stav serveru")
        .task {
            await checkConnection()
        }
    }

    private func checkConnection() async {
        isChecking = true
        errorMessage = nil

        do {
            // Ensure URL doesn't have trailing slash, then add /health
            let cleanURL = url.hasSuffix("/") ? String(url.dropLast()) : url
            guard let healthURL = URL(string: "\(cleanURL)/health") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            // Parse response
            if let json = try? JSONDecoder().decode(HealthResponse.self, from: data) {
                serverVersion = json.version
                isConnected = json.status == "healthy"
            } else {
                isConnected = true
            }
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
        }

        isChecking = false
    }

    struct HealthResponse: Decodable {
        let status: String
        let version: String?
    }
}

// MARK: - Export Formats View

struct ExportFormatsView: View {
    @Binding var selectedFormats: String

    private var formats: Set<String> {
        Set(selectedFormats.split(separator: ",").map(String.init))
    }

    private func toggleFormat(_ format: String) {
        var current = formats
        if current.contains(format) {
            current.remove(format)
        } else {
            current.insert(format)
        }
        selectedFormats = current.sorted().joined(separator: ",")
    }

    var body: some View {
        List {
            Section {
                FormatRow(
                    format: "usdz",
                    name: "USDZ",
                    description: "Apple AR formát pro iOS/macOS",
                    isSelected: formats.contains("usdz"),
                    onToggle: { toggleFormat("usdz") }
                )

                FormatRow(
                    format: "gltf",
                    name: "glTF",
                    description: "Univerzální 3D formát pro web",
                    isSelected: formats.contains("gltf"),
                    onToggle: { toggleFormat("gltf") }
                )

                FormatRow(
                    format: "obj",
                    name: "OBJ",
                    description: "Wavefront OBJ pro 3D software",
                    isSelected: formats.contains("obj"),
                    onToggle: { toggleFormat("obj") }
                )

                FormatRow(
                    format: "stl",
                    name: "STL",
                    description: "Formát pro 3D tisk",
                    isSelected: formats.contains("stl"),
                    onToggle: { toggleFormat("stl") }
                )

                FormatRow(
                    format: "ply",
                    name: "PLY",
                    description: "Point cloud formát",
                    isSelected: formats.contains("ply"),
                    onToggle: { toggleFormat("ply") }
                )
            } footer: {
                Text("Vyberte formáty, které chcete stahovat po zpracování.")
            }
        }
        .navigationTitle("Výstupní formáty")
    }
}

struct FormatRow: View {
    let format: String
    let name: String
    let description: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - Diagnostics Detail View

struct DiagnosticsDetailView: View {
    @State private var diagnosticsJSON: String = "Načítám..."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary
                GroupBox("Souhrn") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Crash reporty:")
                            Spacer()
                            Text("\(CrashReporter.shared.getDiagnostics().count)")
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text("Metriky:")
                            Spacer()
                            Text("\(CrashReporter.shared.getMetrics().count)")
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.subheadline)
                }

                // Raw data
                GroupBox("Raw Data (JSON)") {
                    Text(diagnosticsJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("Diagnostika")
        .onAppear {
            loadDiagnostics()
        }
    }

    private func loadDiagnostics() {
        if let json = CrashReporter.shared.exportDiagnosticsJSON() {
            diagnosticsJSON = json
        } else {
            diagnosticsJSON = "Žádná diagnostická data k dispozici.\n\nData se sbírají automaticky a doručují do 24 hodin po pádu aplikace."
        }
    }
}

// MARK: - Debug Categories View

#if DEBUG
struct DebugCategoriesView: View {
    private var settings: DebugSettings { DebugSettings.shared }

    var body: some View {
        List {
            Section {
                ForEach(DebugCategory.allCases) { category in
                    Toggle(isOn: Binding(
                        get: { settings.enabledCategories.contains(category) },
                        set: { enabled in
                            var categories = settings.enabledCategories
                            if enabled {
                                categories.insert(category)
                            } else {
                                categories.remove(category)
                            }
                            settings.enabledCategories = categories
                        }
                    )) {
                        Label {
                            Text(category.displayName)
                        } icon: {
                            Image(systemName: category.icon)
                        }
                    }
                }
            } footer: {
                Text("Vyberte kategorie dat, které chcete streamovat na debug server.")
            }

            Section {
                Button("Povolit vše") {
                    settings.enabledCategories = Set(DebugCategory.allCases)
                }

                Button("Zakázat vše") {
                    settings.enabledCategories = []
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Debug Categories")
    }
}
#endif

#Preview {
    SettingsView()
}
