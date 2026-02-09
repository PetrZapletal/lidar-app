import Foundation
import UIKit

/// Codable metadata for persisting ScanModel to disk
private struct ScanMetadata: Codable {
    let id: String
    var name: String
    let createdAt: Date
    let pointCount: Int
    let faceCount: Int
    let fileSize: Int64
    let isProcessed: Bool

    init(from scan: ScanModel) {
        self.id = scan.id
        self.name = scan.name
        self.createdAt = scan.createdAt
        self.pointCount = scan.pointCount
        self.faceCount = scan.faceCount
        self.fileSize = scan.fileSize
        self.isProcessed = scan.isProcessed
    }

    func toScanModel(localURL: URL?, thumbnail: UIImage?) -> ScanModel {
        ScanModel(
            id: id,
            name: name,
            createdAt: createdAt,
            thumbnail: thumbnail,
            pointCount: pointCount,
            faceCount: faceCount,
            fileSize: fileSize,
            isProcessed: isProcessed,
            localURL: localURL
        )
    }
}

/// Service for local scan persistence in Documents/Scans/
@Observable
@MainActor
final class PersistenceService: PersistenceServiceProtocol {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let scansDirectory: URL
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    // MARK: - Init

    init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.scansDirectory = documentsURL.appendingPathComponent("Scans", isDirectory: true)

        self.jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601

        try? fileManager.createDirectory(at: scansDirectory, withIntermediateDirectories: true)

        debugLog("PersistenceService initialized at \(scansDirectory.path)", category: .logCategoryStorage)
    }

    // MARK: - PersistenceServiceProtocol

    func saveScan(_ scan: ScanModel) async throws {
        let scanDir = scansDirectory.appendingPathComponent(scan.id, isDirectory: true)
        try fileManager.createDirectory(at: scanDir, withIntermediateDirectories: true)

        // Save metadata
        let metadata = ScanMetadata(from: scan)
        let metadataURL = scanDir.appendingPathComponent("metadata.json")
        let data = try jsonEncoder.encode(metadata)
        try data.write(to: metadataURL)

        // Save thumbnail if available
        if let thumbnail = scan.thumbnail, let jpegData = thumbnail.jpegData(compressionQuality: 0.8) {
            let thumbnailURL = scanDir.appendingPathComponent("thumbnail.jpg")
            try jpegData.write(to: thumbnailURL)
        }

        // Copy mesh file if localURL points to a file outside the scan directory
        if let localURL = scan.localURL, fileManager.fileExists(atPath: localURL.path) {
            let destURL = scanDir.appendingPathComponent(localURL.lastPathComponent)
            if localURL != destURL {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: localURL, to: destURL)
            }
        }

        debugLog("Scan saved: \(scan.name) (\(scan.id))", category: .logCategoryStorage)
    }

    func loadScans() async throws -> [ScanModel] {
        guard fileManager.fileExists(atPath: scansDirectory.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: scansDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var scans: [ScanModel] = []

        for scanDir in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: scanDir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let metadataURL = scanDir.appendingPathComponent("metadata.json")
            guard fileManager.fileExists(atPath: metadataURL.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: metadataURL)
                let metadata = try jsonDecoder.decode(ScanMetadata.self, from: data)

                // Load thumbnail
                let thumbnailURL = scanDir.appendingPathComponent("thumbnail.jpg")
                let thumbnail: UIImage? = fileManager.fileExists(atPath: thumbnailURL.path)
                    ? UIImage(contentsOfFile: thumbnailURL.path)
                    : nil

                let scan = metadata.toScanModel(localURL: scanDir, thumbnail: thumbnail)
                scans.append(scan)
            } catch {
                errorLog("Failed to load scan at \(scanDir.lastPathComponent): \(error.localizedDescription)", category: .logCategoryStorage)
            }
        }

        debugLog("Loaded \(scans.count) scans", category: .logCategoryStorage)
        return scans
    }

    func deleteScan(id: UUID) async throws {
        let scanDir = scansDirectory.appendingPathComponent(id.uuidString, isDirectory: true)

        guard fileManager.fileExists(atPath: scanDir.path) else {
            debugLog("Scan directory not found for deletion: \(id)", category: .logCategoryStorage)
            return
        }

        try fileManager.removeItem(at: scanDir)
        debugLog("Scan deleted: \(id)", category: .logCategoryStorage)
    }

    func scanFileURL(id: UUID, format: ExportFormat) -> URL? {
        let scanDir = scansDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let fileURL = scanDir.appendingPathComponent("model.\(format.fileExtension)")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return fileURL
    }
}
