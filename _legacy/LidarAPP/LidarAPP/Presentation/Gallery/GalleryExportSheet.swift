import SwiftUI

struct GalleryExportSheet: View {
    let scan: ScanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExportCategory.allCases, id: \.self) { category in
                    let formats = ExportFormat.allCases.filter { $0.category == category }
                    if !formats.isEmpty {
                        Section(category.rawValue) {
                            ForEach(formats) { format in
                                GalleryExportFormatRow(format: format)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Exportovat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hotovo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct GalleryExportFormatRow: View {
    let format: ExportFormat

    var body: some View {
        Button(action: { /* export */ }) {
            HStack {
                Image(systemName: format.icon)
                    .frame(width: 30)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading) {
                    Text(format.displayName)
                        .fontWeight(.medium)
                    Text(format.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
            }
        }
        .foregroundStyle(.primary)
    }
}
