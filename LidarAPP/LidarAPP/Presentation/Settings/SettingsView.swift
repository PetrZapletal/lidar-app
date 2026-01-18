import SwiftUI

/// Main settings view
struct SettingsView: View {
    @AppStorage("backendURL") private var backendURL = "https://api.lidarscanner.app"
    @AppStorage("enableDepthFusion") private var enableDepthFusion = true
    @AppStorage("targetPointCount") private var targetPointCount = 500_000
    @AppStorage("meshResolution") private var meshResolution = "high"
    @AppStorage("textureResolution") private var textureResolution = 4096
    @AppStorage("autoUpload") private var autoUpload = true
    @AppStorage("outputFormats") private var outputFormatsString = "usdz,gltf"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                backendSection
                processingSection
                qualitySection
                exportSection
                aboutSection
            }
            .navigationTitle("Nastavení")
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
            guard let baseURL = URL(string: url) else {
                throw URLError(.badURL)
            }

            let healthURL = baseURL.appendingPathComponent("/")
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

// MARK: - Bundle Extensions

extension Bundle {
    var appVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

#Preview {
    SettingsView()
}
