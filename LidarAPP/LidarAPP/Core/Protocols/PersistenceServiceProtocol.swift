import Foundation

/// Protokol pro lokální úložiště skenů
@MainActor
protocol PersistenceServiceProtocol: AnyObject {
    /// Ulož scan
    func saveScan(_ scan: ScanModel) async throws

    /// Načti všechny scany
    func loadScans() async throws -> [ScanModel]

    /// Smaž scan
    func deleteScan(id: UUID) async throws

    /// Získej cestu k souboru scanu
    func scanFileURL(id: UUID, format: ExportFormat) -> URL?
}

// MARK: - Placeholder (Sprint 0)

@MainActor
final class PlaceholderPersistenceService: PersistenceServiceProtocol {
    func saveScan(_ scan: ScanModel) async throws {
        debugLog("PlaceholderPersistenceService: saveScan not implemented", category: .logCategoryStorage)
    }

    func loadScans() async throws -> [ScanModel] { [] }

    func deleteScan(id: UUID) async throws {}

    func scanFileURL(id: UUID, format: ExportFormat) -> URL? { nil }
}
