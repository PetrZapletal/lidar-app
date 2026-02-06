import SwiftUI

struct GalleryView: View {
    let scanStore: ScanStore
    @State private var searchText = ""
    @State private var selectedScan: ScanModel?
    @State private var sortOrder: ScanSortOrder = .dateDescending
    @State private var viewMode: ViewMode = .grid

    enum ViewMode {
        case grid
        case list
    }

    var filteredScans: [ScanModel] {
        var scans = scanStore.scans
        if !searchText.isEmpty {
            scans = scans.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return scans.sorted(by: sortOrder)
    }

    var body: some View {
        NavigationStack {
            Group {
                if scanStore.scans.isEmpty {
                    emptyStateView
                } else {
                    scanGridView
                }
            }
            .navigationTitle("Moje 3D modely")
            .searchable(text: $searchText, prompt: "Hledat modely")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Řazení", selection: $sortOrder) {
                            ForEach(ScanSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }

                        Divider()

                        Button(action: { viewMode = .grid }) {
                            Label("Mřížka", systemImage: "square.grid.2x2")
                        }
                        Button(action: { viewMode = .list }) {
                            Label("Seznam", systemImage: "list.bullet")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
            .navigationDestination(item: $selectedScan) { scan in
                ModelDetailView(scan: scan, scanStore: scanStore)
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("Žádné modely", systemImage: "cube.transparent")
        } description: {
            Text("Vytvořte svůj první 3D sken pomocí tlačítka skenování")
        } actions: {
            Text("Stiskněte modré tlačítko dole")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scanGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(filteredScans) { scan in
                    ScanGridCard(scan: scan)
                        .onTapGesture {
                            selectedScan = scan
                        }
                }
            }
            .padding()
        }
    }
}

// MARK: - Scan Grid Card

struct ScanGridCard: View {
    let scan: ScanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(1, contentMode: .fit)

                if let thumbnail = scan.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue.opacity(0.5))
                }

                VStack {
                    HStack {
                        Spacer()
                        if scan.isProcessed {
                            Label("AI", systemImage: "wand.and.stars")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.green)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(scan.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(scan.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Text("•")
                    Text(formatFileSize(scan.fileSize))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
