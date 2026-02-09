import SwiftUI

/// ViewModel pro galerii skenu
@MainActor
@Observable
final class GalleryViewModel {

    // MARK: - Dependencies

    private let services: ServiceContainer

    // MARK: - State

    var scans: [ScanModel] = []
    var isLoading: Bool = false
    var sortOrder: ScanSortOrder = .dateDescending
    var searchText: String = ""
    var errorMessage: String?

    // MARK: - Computed

    var filteredScans: [ScanModel] {
        var result = scans
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return result.sorted(by: sortOrder)
    }

    // MARK: - Init

    init(services: ServiceContainer) {
        self.services = services
    }

    // MARK: - Methods

    func loadScans() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                scans = try await services.persistence.loadScans()
                debugLog("Loaded \(scans.count) scans", category: .logCategoryStorage)
            } catch {
                errorLog("Failed to load scans: \(error.localizedDescription)", category: .logCategoryStorage)
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func deleteScan(_ scan: ScanModel) {
        Task {
            do {
                if let uuid = UUID(uuidString: scan.id) {
                    try await services.persistence.deleteScan(id: uuid)
                }
                scans.removeAll { $0.id == scan.id }
                debugLog("Deleted scan: \(scan.name)", category: .logCategoryStorage)
            } catch {
                errorLog("Failed to delete scan: \(error.localizedDescription)", category: .logCategoryStorage)
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshScans() {
        loadScans()
    }
}
