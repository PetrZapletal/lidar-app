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


