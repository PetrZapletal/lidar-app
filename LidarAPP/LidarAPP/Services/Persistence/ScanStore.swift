import Foundation
import UIKit

@Observable
final class ScanStore {
    var scans: [ScanModel] = []

    /// Stores actual 3D data (point clouds, meshes) by scan ID
    private var scanSessions: [String: ScanSession] = [:]
    private let persistence = ScanSessionPersistence()

    func loadScans() async {
        // Load persisted sessions from disk
        let persistedSessions = await persistence.listSavedSessions()
        for persisted in persistedSessions {
            let scanModel = ScanModel(
                id: persisted.id.uuidString,
                name: persisted.name,
                createdAt: persisted.createdAt,
                thumbnail: nil,
                pointCount: persisted.totalVertices,
                faceCount: persisted.totalFaces,
                fileSize: Int64(await persistence.storageUsed(sessionId: persisted.id)),
                isProcessed: persisted.state == "completed",
                localURL: nil
            )
            if !scans.contains(where: { $0.id == scanModel.id }) {
                scans.append(scanModel)
            }
        }

        // Fallback: load mock data if in mock mode and nothing persisted
        if MockDataProvider.isMockModeEnabled && scans.isEmpty {
            loadMockScans()
        }
    }

    private func loadMockScans() {
        let mockProvider = MockDataProvider.shared

        let mockScan1 = ScanModel(
            id: UUID().uuidString,
            name: "Obyvaci pokoj",
            createdAt: Date().addingTimeInterval(-86400),
            thumbnail: nil,
            pointCount: 125000,
            faceCount: 42000,
            fileSize: 15_000_000,
            isProcessed: true,
            localURL: nil
        )
        let session1 = mockProvider.createMockScanSession(name: "Obyvaci pokoj")
        addScan(mockScan1, session: session1)

        let mockScan2 = ScanModel(
            id: UUID().uuidString,
            name: "Kuchyn",
            createdAt: Date().addingTimeInterval(-172800),
            thumbnail: nil,
            pointCount: 85000,
            faceCount: 28000,
            fileSize: 10_500_000,
            isProcessed: true,
            localURL: nil
        )
        let session2 = mockProvider.createMockScanSession(name: "Kuchyn")
        addScan(mockScan2, session: session2)

        let mockScan3 = ScanModel(
            id: UUID().uuidString,
            name: "Loznice",
            createdAt: Date().addingTimeInterval(-259200),
            thumbnail: nil,
            pointCount: 95000,
            faceCount: 32000,
            fileSize: 12_000_000,
            isProcessed: false,
            localURL: nil
        )
        let session3 = mockProvider.createMockScanSession(name: "Loznice")
        addScan(mockScan3, session: session3)
    }

    func addScan(_ scan: ScanModel) {
        scans.insert(scan, at: 0)
    }

    func addScan(_ scan: ScanModel, session: ScanSession) {
        scans.insert(scan, at: 0)
        scanSessions[scan.id] = session

        // Persist to disk asynchronously
        Task {
            do {
                _ = try await persistence.saveSession(session, chunkManager: nil)
            } catch {
                print("Failed to persist scan: \(error)")
            }
        }
    }

    func getSession(for scanId: String) -> ScanSession? {
        scanSessions[scanId]
    }

    func deleteScan(_ scan: ScanModel) {
        scans.removeAll { $0.id == scan.id }
        scanSessions.removeValue(forKey: scan.id)

        // Delete from disk
        if let uuid = UUID(uuidString: scan.id) {
            Task {
                try? await persistence.deleteSession(id: uuid)
            }
        }
    }

    func renameScan(_ scan: ScanModel, to newName: String) {
        if let index = scans.firstIndex(where: { $0.id == scan.id }) {
            scans[index].name = newName
        }
    }

    /// Get existing session or create a mock one for testing
    func getOrCreateSession(for scan: ScanModel) -> ScanSession {
        if let existing = scanSessions[scan.id] {
            return existing
        }

        let mockSession = MockDataProvider.shared.createMockScanSession(name: scan.name)
        scanSessions[scan.id] = mockSession
        return mockSession
    }
}
