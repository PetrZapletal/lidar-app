import SwiftUI

/// Detail skenu s 3D nahledem, metadaty a akcemi
struct ModelDetailView: View {
    let scan: ScanModel
    let services: ServiceContainer

    @State private var previewViewModel: PreviewViewModel
    @State private var showExportPicker = false
    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var exportedURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?
    @Environment(\.dismiss) private var dismiss

    init(scan: ScanModel, services: ServiceContainer) {
        self.scan = scan
        self.services = services
        self._previewViewModel = State(initialValue: PreviewViewModel(services: services))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 3D Preview
                previewSection

                // Metadata
                metadataSection

                // Actions
                actionsSection
            }
        }
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showExportPicker = true }) {
                        Label("Exportovat", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive, action: { showDeleteAlert = true }) {
                        Label("Smazat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            previewViewModel.loadMesh(from: scan)
        }
        .confirmationDialog("Exportovat jako", isPresented: $showExportPicker) {
            ForEach(services.export.supportedFormats) { format in
                Button(format.rawValue) {
                    exportScan(format: format)
                }
            }
            Button("Zrusit", role: .cancel) {}
        }
        .alert("Smazat model?", isPresented: $showDeleteAlert) {
            Button("Zrusit", role: .cancel) {}
            Button("Smazat", role: .destructive) {
                deleteScan()
            }
        } message: {
            Text("Tato akce je nevratna. Model \"\(scan.name)\" bude trvale smazan.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(spacing: 0) {
            ModelPreviewView(
                meshData: previewViewModel.meshData,
                displayMode: previewViewModel.displayMode
            )
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.top, 8)

            // Display mode picker
            Picker("Rezim", selection: $previewViewModel.displayMode) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Informace")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetadataCell(title: "Nazev", value: scan.name, icon: "textformat")
                MetadataCell(title: "Datum", value: scan.createdAt.formatted(date: .abbreviated, time: .shortened), icon: "calendar")
                MetadataCell(title: "Body", value: formatCount(scan.pointCount), icon: "circle.grid.3x3")
                MetadataCell(title: "Plosky", value: formatCount(scan.faceCount), icon: "triangle")
                MetadataCell(title: "Velikost", value: formatFileSize(scan.fileSize), icon: "doc")
                MetadataCell(
                    title: "Stav",
                    value: scan.isProcessed ? "Zpracovano" : "Zakladni",
                    icon: scan.isProcessed ? "checkmark.circle.fill" : "clock"
                )
            }
        }
        .padding()
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: { showExportPicker = true }) {
                Label("Exportovat model", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isExporting)

            if isExporting {
                ProgressView("Exportuji...")
            }

            if let error = exportError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(role: .destructive, action: { showDeleteAlert = true }) {
                Label("Smazat model", systemImage: "trash")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func exportScan(format: ExportFormat) {
        guard let meshData = previewViewModel.meshData else {
            exportError = "Zadna data k exportu"
            return
        }

        isExporting = true
        exportError = nil

        Task {
            do {
                let url = try await services.export.export(
                    meshData: meshData,
                    format: format,
                    name: scan.name
                )
                exportedURL = url
                showShareSheet = true
                debugLog("Exported \(scan.name) as \(format.rawValue)", category: .logCategoryUI)
            } catch {
                errorLog("Export failed: \(error.localizedDescription)", category: .logCategoryUI)
                exportError = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func deleteScan() {
        Task {
            do {
                if let uuid = UUID(uuidString: scan.id) {
                    try await services.persistence.deleteScan(id: uuid)
                }
                debugLog("Deleted scan: \(scan.name)", category: .logCategoryUI)
                dismiss()
            } catch {
                errorLog("Delete failed: \(error.localizedDescription)", category: .logCategoryUI)
            }
        }
    }

    // MARK: - Formatting

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Metadata Cell

private struct MetadataCell: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
