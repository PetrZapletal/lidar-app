import SwiftUI

/// Galerie ulozenych 3D skenu
struct GalleryView: View {
    let services: ServiceContainer
    @State private var viewModel: GalleryViewModel
    @State private var selectedScan: ScanModel?

    init(services: ServiceContainer) {
        self.services = services
        self._viewModel = State(initialValue: GalleryViewModel(services: services))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.scans.isEmpty {
                    ProgressView("Nacitam...")
                } else if viewModel.filteredScans.isEmpty {
                    emptyStateView
                } else {
                    scanGridView
                }
            }
            .navigationTitle("Galerie")
            .searchable(text: $viewModel.searchText, prompt: "Hledat modely")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Razeni", selection: $viewModel.sortOrder) {
                            ForEach(ScanSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
            .refreshable {
                viewModel.refreshScans()
            }
            .onAppear {
                viewModel.loadScans()
            }
            .navigationDestination(item: $selectedScan) { scan in
                ModelDetailView(scan: scan, services: services)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("Zadne modely", systemImage: "cube.transparent")
        } description: {
            Text("Vytvorte svuj prvni 3D sken pomoci tlacitka skenovani")
        } actions: {
            Text("Stisknete modre tlacitko dole")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Grid

    private var scanGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(viewModel.filteredScans) { scan in
                    ScanGridCard(scan: scan)
                        .onTapGesture {
                            selectedScan = scan
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteScan(scan)
                            } label: {
                                Label("Smazat", systemImage: "trash")
                            }
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
                    Text("\u{2022}")
                    Text(formatPointCount(scan.pointCount))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func formatPointCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM bodu", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK bodu", Double(count) / 1_000)
        }
        return "\(count) bodu"
    }
}
