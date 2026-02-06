import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    // 3D Mesh
    case obj
    case ply
    case stl
    case gltf
    case usdz

    // Point Cloud
    case plyPointCloud = "ply_pc"

    // Documents
    case json
    case csv
    case pdf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .obj: return "OBJ (Wavefront)"
        case .ply: return "PLY (Polygon)"
        case .stl: return "STL (3D Print)"
        case .gltf: return "glTF (Web)"
        case .usdz: return "USDZ (Apple AR)"
        case .plyPointCloud: return "PLY (Point Cloud)"
        case .json: return "JSON (Měření)"
        case .csv: return "CSV (Měření)"
        case .pdf: return "PDF (Zpráva)"
        }
    }

    var fileExtension: String {
        switch self {
        case .obj: return "obj"
        case .ply, .plyPointCloud: return "ply"
        case .stl: return "stl"
        case .gltf: return "gltf"
        case .usdz: return "usdz"
        case .json: return "json"
        case .csv: return "csv"
        case .pdf: return "pdf"
        }
    }

    var icon: String {
        switch self {
        case .obj: return "cube"
        case .ply: return "cube.fill"
        case .stl: return "printer.fill"
        case .gltf: return "globe"
        case .usdz: return "arkit"
        case .plyPointCloud: return "circle.dotted"
        case .json: return "doc.text"
        case .csv: return "tablecells"
        case .pdf: return "doc.richtext"
        }
    }

    var category: ExportCategory {
        switch self {
        case .obj, .ply, .stl, .gltf, .usdz:
            return .mesh
        case .plyPointCloud:
            return .pointCloud
        case .json, .csv, .pdf:
            return .document
        }
    }

    var description: String {
        switch self {
        case .obj: return "Universální 3D formát pro většinu aplikací"
        case .ply: return "Polygon formát s barvami a normálami"
        case .stl: return "Formát pro 3D tisk bez barev"
        case .gltf: return "Moderní formát pro web a hry"
        case .usdz: return "Apple AR Quick Look formát"
        case .plyPointCloud: return "Surový point cloud s barvami"
        case .json: return "Strukturovaná data měření"
        case .csv: return "Tabulkový formát pro Excel"
        case .pdf: return "Kompletní zpráva s obrázky"
        }
    }

    // Static format collections for convenience
    static var meshFormats: [ExportFormat] {
        [.usdz, .gltf, .obj, .stl, .ply]
    }

    static var dataFormats: [ExportFormat] {
        [.json, .csv]
    }
}

enum ExportCategory: String, CaseIterable {
    case mesh = "3D Mesh"
    case pointCloud = "Point Cloud"
    case document = "Dokumenty"
}

// MARK: - Export View

struct ExportView: View {
    let session: ScanSession
    let scanName: String
    @State private var viewModel: ExportViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: ScanSession, scanName: String) {
        self.session = session
        self.scanName = scanName
        self._viewModel = State(wrappedValue: ExportViewModel(session: session, scanName: scanName))
    }

    var body: some View {
        NavigationStack {
            List {
                // Preview section
                Section {
                    exportPreviewHeader
                }

                // Export options by category
                ForEach(ExportCategory.allCases, id: \.self) { category in
                    let formats = ExportFormat.allCases.filter { $0.category == category }
                    if !formats.isEmpty && isFormatCategoryAvailable(category) {
                        Section(header: Text(category.rawValue)) {
                            ForEach(formats) { format in
                                ExportFormatRow(
                                    format: format,
                                    isSelected: viewModel.selectedFormat == format,
                                    isExporting: viewModel.isExporting && viewModel.selectedFormat == format
                                ) {
                                    viewModel.selectedFormat = format
                                }
                            }
                        }
                    }
                }

                // Export options
                if viewModel.selectedFormat != nil {
                    Section(header: Text("Možnosti")) {
                        exportOptionsSection
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zrušit") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Exportovat") {
                        Task {
                            await viewModel.export()
                        }
                    }
                    .disabled(viewModel.selectedFormat == nil || viewModel.isExporting)
                    .fontWeight(.semibold)
                }
            }
            .overlay {
                if viewModel.isExporting {
                    exportProgressOverlay
                }
            }
            .alert("Export dokončen", isPresented: $viewModel.showSuccess) {
                Button("Sdílet") {
                    viewModel.shareExportedFile()
                }
                Button("Hotovo", role: .cancel) {
                    dismiss()
                }
            } message: {
                if let result = viewModel.exportResult {
                    Text("Soubor \(result.format.displayName) byl vytvořen (\(formatFileSize(result.fileSize)))")
                }
            }
            .alert("Chyba exportu", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Neznámá chyba")
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                if let url = viewModel.exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private var exportPreviewHeader: some View {
        HStack(spacing: 16) {
            // 3D thumbnail placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 80, height: 80)

                Image(systemName: "cube.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(scanName)
                    .font(.headline)

                Group {
                    if let pc = session.pointCloud {
                        Text("\(pc.pointCount.formatted()) bodů")
                    }
                    Text("\(session.faceCount.formatted()) ploch")
                    Text("Měření: \(session.measurements.count)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var exportOptionsSection: some View {
        if let format = viewModel.selectedFormat {
            switch format.category {
            case .mesh:
                Toggle("Zahrnout normály", isOn: $viewModel.includeNormals)
                Toggle("Zahrnout barvy", isOn: $viewModel.includeColors)

                Picker("Souřadnicový systém", selection: $viewModel.coordinateSystem) {
                    Text("Y-nahoru (Standard)").tag(ExportService.ExportOptions.CoordinateSystem.yUp)
                    Text("Z-nahoru (CAD)").tag(ExportService.ExportOptions.CoordinateSystem.zUp)
                }

                if format == .stl {
                    Toggle("Binární formát", isOn: $viewModel.binaryFormat)
                }

            case .pointCloud:
                Toggle("Zahrnout barvy", isOn: $viewModel.includeColors)
                Toggle("Zahrnout normály", isOn: $viewModel.includeNormals)

            case .document:
                if format == .pdf {
                    Toggle("Zahrnout obrázky", isOn: $viewModel.includeImages)
                    Toggle("Zahrnout měření", isOn: $viewModel.includeMeasurements)
                }
            }
        }
    }

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Exportuji...")
                    .font(.headline)
                    .foregroundStyle(.white)

                if let format = viewModel.selectedFormat {
                    Text(format.displayName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func isFormatCategoryAvailable(_ category: ExportCategory) -> Bool {
        switch category {
        case .mesh:
            return session.faceCount > 0 || !session.combinedMesh.meshes.isEmpty
        case .pointCloud:
            return session.pointCloud != nil && session.pointCloud!.pointCount > 0
        case .document:
            return true
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Export Format Row

struct ExportFormatRow: View {
    let format: ExportFormat
    let isSelected: Bool
    let isExporting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: format.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(format.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(format.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isExporting {
                    ProgressView()
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Export View Model

@MainActor
@Observable
final class ExportViewModel {
    let session: ScanSession
    let scanName: String

    var selectedFormat: ExportFormat?
    var isExporting = false
    var showSuccess = false
    var showError = false
    var showShareSheet = false
    var errorMessage: String?
    var exportResult: ExportService.ExportResult?
    var exportedFileURL: URL?

    // Export options
    var includeNormals = true
    var includeColors = true
    var coordinateSystem: ExportService.ExportOptions.CoordinateSystem = .yUp
    var binaryFormat = false
    var includeImages = true
    var includeMeasurements = true

    private let exportService = ExportService()

    init(session: ScanSession, scanName: String) {
        self.session = session
        self.scanName = scanName
    }

    func export() async {
        guard let format = selectedFormat else { return }

        isExporting = true
        errorMessage = nil

        do {
            let result: ExportService.ExportResult

            switch format.category {
            case .mesh:
                guard let mesh = session.combinedMesh.toUnifiedMesh() else {
                    throw ExportError.exportFailed("Žádná mesh data k exportu")
                }

                let options = ExportService.ExportOptions(
                    includeNormals: includeNormals,
                    includeColors: includeColors,
                    includeTextures: false,
                    simplifyMesh: false,
                    simplificationRatio: 1.0,
                    coordinateSystem: coordinateSystem
                )

                result = try await exportService.exportMesh(mesh, format: format, name: scanName, options: options)

            case .pointCloud:
                guard let pointCloud = session.pointCloud else {
                    throw ExportError.exportFailed("Žádný point cloud k exportu")
                }

                result = try await exportService.exportPointCloud(pointCloud, format: .ply, name: scanName)

            case .document:
                result = try await exportService.exportMeasurements(
                    session.measurements,
                    format: format,
                    name: scanName
                )
            }

            exportResult = result
            exportedFileURL = result.url
            showSuccess = true

        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isExporting = false
    }

    func shareExportedFile() {
        showShareSheet = true
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    ExportView(
        session: MockDataProvider.shared.createMockScanSession(),
        scanName: "Test Scan"
    )
}
