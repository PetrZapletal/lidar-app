import Foundation
import ARKit
import simd

/// Handles saving and loading scan sessions with ARWorldMap for resumable scanning
actor ScanSessionPersistence {

    // MARK: - Persistence Data Structures

    struct PersistedSession: Codable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let createdAt: Date
        let updatedAt: Date
        let state: String

        let deviceModel: String
        let appVersion: String

        // References to chunked data files
        let meshChunkFiles: [String]
        let pointCloudChunkFiles: [String]
        let textureFrameFiles: [String]

        // ARWorldMap file reference
        let worldMapFile: String?

        // Camera trajectory file
        let trajectoryFile: String?

        // Coverage data file
        let coverageDataFile: String?

        // Statistics
        let scanDuration: TimeInterval
        let totalVertices: Int
        let totalFaces: Int
        let areaScanned: Float

        // Thumbnail
        let thumbnailFile: String?
    }

    struct Checkpoint: Codable, Sendable {
        let sessionId: UUID
        let timestamp: Date
        let lastProcessedMeshAnchorId: String?
        let lastFrameTimestamp: TimeInterval
        let meshChunkCount: Int
        let pointCount: Int
        let coverageSnapshotFile: String?
    }

    struct TextureFrameReference: Codable, Sendable {
        let id: UUID
        let timestamp: TimeInterval
        let fileName: String
        let resolution: CGSize
        let cameraTransformData: Data // Serialized simd_float4x4
        let intrinsicsData: Data // Serialized simd_float3x3
    }

    // MARK: - Configuration

    private let baseDirectory: URL
    private let checkpointInterval: TimeInterval = 30 // Auto-save every 30 seconds
    private var lastCheckpointTime: Date = .distantPast

    // MARK: - Initialization

    init() {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.baseDirectory = documentsDir.appendingPathComponent("ScanSessions")
        // Directory will be created on first use
    }

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    /// Ensure base directory exists (call before operations)
    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Save Operations

    /// Save a complete scan session to disk
    func saveSession(_ session: ScanSession, chunkManager: ChunkManager?) async throws -> URL {
        try ensureDirectoryExists()
        let sessionDir = baseDirectory.appendingPathComponent(session.id.uuidString)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        // Save mesh chunks metadata
        var meshChunkFiles: [String] = []
        if let chunkManager = chunkManager {
            let metadata = await chunkManager.getAllMetadata()
            for chunk in metadata {
                meshChunkFiles.append(chunk.fileName)
            }
            try await chunkManager.saveMetadataIndex()
        }

        // Save texture frame references
        var textureFrameFiles: [String] = []
        for (index, frame) in session.textureFrames.enumerated() {
            let fileName = "texture_\(index)_\(frame.id.uuidString).heic"
            let frameURL = sessionDir.appendingPathComponent(fileName)

            // Save image data
            try frame.imageData.write(to: frameURL)
            textureFrameFiles.append(fileName)

            // Save metadata
            let reference = TextureFrameReference(
                id: frame.id,
                timestamp: frame.timestamp,
                fileName: fileName,
                resolution: frame.resolution,
                cameraTransformData: serializeMatrix(frame.cameraTransform),
                intrinsicsData: serializeMatrix3x3(frame.intrinsics)
            )

            let refData = try JSONEncoder().encode(reference)
            let refURL = sessionDir.appendingPathComponent("texture_\(index)_meta.json")
            try refData.write(to: refURL)
        }

        // Save camera trajectory
        var trajectoryFile: String?
        if !session.deviceTrajectory.isEmpty {
            let fileName = "trajectory.bin"
            let trajectoryURL = sessionDir.appendingPathComponent(fileName)
            let trajectoryData = serializeTrajectory(session.deviceTrajectory)
            try trajectoryData.write(to: trajectoryURL)
            trajectoryFile = fileName
        }

        // Create and save manifest
        let manifest = PersistedSession(
            id: session.id,
            name: session.name,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            state: session.state.rawValue,
            deviceModel: session.deviceModel,
            appVersion: session.appVersion,
            meshChunkFiles: meshChunkFiles,
            pointCloudChunkFiles: [],
            textureFrameFiles: textureFrameFiles,
            worldMapFile: nil,
            trajectoryFile: trajectoryFile,
            coverageDataFile: nil,
            scanDuration: session.scanDuration,
            totalVertices: session.vertexCount,
            totalFaces: session.faceCount,
            areaScanned: session.areaScanned,
            thumbnailFile: nil
        )

        let manifestURL = sessionDir.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL)

        return sessionDir
    }

    /// Save ARWorldMap for session resumption
    func saveWorldMap(_ worldMap: ARWorldMap, sessionId: UUID) async throws -> URL {
        try ensureDirectoryExists()
        let sessionDir = baseDirectory.appendingPathComponent(sessionId.uuidString)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let worldMapURL = sessionDir.appendingPathComponent("worldmap.arworldmap")

        let data = try NSKeyedArchiver.archivedData(
            withRootObject: worldMap,
            requiringSecureCoding: true
        )
        try data.write(to: worldMapURL)

        // Update manifest
        try await updateManifestWorldMapFile(sessionId: sessionId, fileName: "worldmap.arworldmap")

        return worldMapURL
    }

    /// Save coverage data for session
    func saveCoverageGrid(_ data: Data, sessionId: UUID) async throws {
        try ensureDirectoryExists()
        let sessionDir = baseDirectory.appendingPathComponent(sessionId.uuidString)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let coverageURL = sessionDir.appendingPathComponent("coverage.bin")
        try data.write(to: coverageURL)

        try await updateManifestCoverageFile(sessionId: sessionId, fileName: "coverage.bin")
    }

    /// Create a checkpoint during scanning (simplified overload)
    func createCheckpoint(session: ScanSession) async throws {
        try await createCheckpoint(session: session, chunkManager: nil, coverageAnalyzer: nil)
    }

    /// Create a checkpoint during scanning
    func createCheckpoint(
        session: ScanSession,
        chunkManager: ChunkManager?,
        coverageAnalyzer: CoverageAnalyzer?
    ) async throws {
        let now = Date()
        guard now.timeIntervalSince(lastCheckpointTime) >= checkpointInterval else { return }
        lastCheckpointTime = now

        try ensureDirectoryExists()
        let sessionDir = baseDirectory.appendingPathComponent(session.id.uuidString)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        // Save coverage snapshot if available
        var coverageFile: String?
        if let analyzer = coverageAnalyzer {
            let coverageData = try await MainActor.run {
                try analyzer.serializeCoverageGrid()
            }
            let fileName = "checkpoint_coverage.bin"
            try coverageData.write(to: sessionDir.appendingPathComponent(fileName))
            coverageFile = fileName
        }

        let chunkCount = await chunkManager?.getAllMetadata().count ?? 0

        let checkpoint = Checkpoint(
            sessionId: session.id,
            timestamp: now,
            lastProcessedMeshAnchorId: nil,
            lastFrameTimestamp: session.textureFrames.last?.timestamp ?? 0,
            meshChunkCount: chunkCount,
            pointCount: session.pointCloud?.pointCount ?? 0,
            coverageSnapshotFile: coverageFile
        )

        let checkpointURL = sessionDir.appendingPathComponent("checkpoint.json")
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: checkpointURL)

        // Also save chunk manager index
        try await chunkManager?.saveMetadataIndex()
    }

    // MARK: - Load Operations

    /// Load a session from disk
    func loadSession(id: UUID) async throws -> PersistedSession {
        let sessionDir = baseDirectory.appendingPathComponent(id.uuidString)
        let manifestURL = sessionDir.appendingPathComponent("manifest.json")

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersistedSession.self, from: data)
    }

    /// Load ARWorldMap for session resumption
    func loadWorldMap(sessionId: UUID) async throws -> ARWorldMap {
        let sessionDir = baseDirectory.appendingPathComponent(sessionId.uuidString)
        let worldMapURL = sessionDir.appendingPathComponent("worldmap.arworldmap")

        guard FileManager.default.fileExists(atPath: worldMapURL.path) else {
            throw PersistenceError.worldMapNotFound
        }

        let data = try Data(contentsOf: worldMapURL)
        guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARWorldMap.self,
            from: data
        ) else {
            throw PersistenceError.invalidWorldMap
        }

        return worldMap
    }

    /// Load checkpoint for session
    func loadCheckpoint(sessionId: UUID) async throws -> Checkpoint? {
        let sessionDir = baseDirectory.appendingPathComponent(sessionId.uuidString)
        let checkpointURL = sessionDir.appendingPathComponent("checkpoint.json")

        guard FileManager.default.fileExists(atPath: checkpointURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: checkpointURL)
        return try JSONDecoder().decode(Checkpoint.self, from: data)
    }

    /// Load coverage data for session
    func loadCoverageGrid(sessionId: UUID) async throws -> Data? {
        let sessionDir = baseDirectory.appendingPathComponent(sessionId.uuidString)
        let coverageURL = sessionDir.appendingPathComponent("coverage.bin")

        guard FileManager.default.fileExists(atPath: coverageURL.path) else {
            return nil
        }

        return try Data(contentsOf: coverageURL)
    }

    /// Load camera trajectory
    func loadTrajectory(sessionId: UUID) async throws -> [simd_float4x4]? {
        let sessionDir = baseDirectory.appendingPathComponent(sessionId.uuidString)
        let trajectoryURL = sessionDir.appendingPathComponent("trajectory.bin")

        guard FileManager.default.fileExists(atPath: trajectoryURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: trajectoryURL)
        return deserializeTrajectory(data)
    }

    /// Load texture frame references
    func loadTextureFrameReferences(sessionId: UUID) async throws -> [TextureFrameReference] {
        let sessionDir = baseDirectory.appendingPathComponent(sessionId.uuidString)
        var references: [TextureFrameReference] = []

        let contents = try FileManager.default.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil)

        for url in contents where url.lastPathComponent.hasPrefix("texture_") && url.lastPathComponent.hasSuffix("_meta.json") {
            let data = try Data(contentsOf: url)
            let reference = try JSONDecoder().decode(TextureFrameReference.self, from: data)
            references.append(reference)
        }

        return references.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Session Discovery

    /// List all saved sessions
    func listSavedSessions() async -> [PersistedSession] {
        var sessions: [PersistedSession] = []

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        for url in contents {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            let manifestURL = url.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL) else { continue }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let manifest = try? decoder.decode(PersistedSession.self, from: data) {
                sessions.append(manifest)
            }
        }

        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// List sessions that can be resumed (have world map)
    func listResumableSessions() async -> [PersistedSession] {
        let all = await listSavedSessions()
        return all.filter { $0.worldMapFile != nil && ($0.state == "paused" || $0.state == "scanning") }
    }

    // MARK: - Delete Operations

    /// Delete a session and all its data
    func deleteSession(id: UUID) async throws {
        let sessionDir = baseDirectory.appendingPathComponent(id.uuidString)
        try FileManager.default.removeItem(at: sessionDir)
    }

    /// Delete all sessions
    func deleteAllSessions() async throws {
        let contents = try FileManager.default.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil)
        for url in contents {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Storage Info

    /// Get total storage used by all sessions
    func totalStorageUsed() async -> Int {
        var totalSize: Int = 0

        guard let enumerator = FileManager.default.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        for case let fileURL as URL in enumerator {
            if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = attributes.fileSize {
                totalSize += fileSize
            }
        }

        return totalSize
    }

    /// Get storage used by a specific session
    func storageUsed(sessionId: UUID) async -> Int {
        let sessionDir = baseDirectory.appendingPathComponent(sessionId.uuidString)
        var totalSize: Int = 0

        guard let enumerator = FileManager.default.enumerator(
            at: sessionDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        for case let fileURL as URL in enumerator {
            if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = attributes.fileSize {
                totalSize += fileSize
            }
        }

        return totalSize
    }

    // MARK: - Private Helpers

    private func updateManifestWorldMapFile(sessionId: UUID, fileName: String) async throws {
        let sessionDir = baseDirectory.appendingPathComponent(sessionId.uuidString)
        let manifestURL = sessionDir.appendingPathComponent("manifest.json")

        let data = try Data(contentsOf: manifestURL)
        var manifest = try JSONDecoder().decode(PersistedSession.self, from: data)

        // Create updated manifest with world map file
        manifest = PersistedSession(
            id: manifest.id,
            name: manifest.name,
            createdAt: manifest.createdAt,
            updatedAt: Date(),
            state: manifest.state,
            deviceModel: manifest.deviceModel,
            appVersion: manifest.appVersion,
            meshChunkFiles: manifest.meshChunkFiles,
            pointCloudChunkFiles: manifest.pointCloudChunkFiles,
            textureFrameFiles: manifest.textureFrameFiles,
            worldMapFile: fileName,
            trajectoryFile: manifest.trajectoryFile,
            coverageDataFile: manifest.coverageDataFile,
            scanDuration: manifest.scanDuration,
            totalVertices: manifest.totalVertices,
            totalFaces: manifest.totalFaces,
            areaScanned: manifest.areaScanned,
            thumbnailFile: manifest.thumbnailFile
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let updatedData = try encoder.encode(manifest)
        try updatedData.write(to: manifestURL)
    }

    private func updateManifestCoverageFile(sessionId: UUID, fileName: String) async throws {
        let sessionDir = baseDirectory.appendingPathComponent(sessionId.uuidString)
        let manifestURL = sessionDir.appendingPathComponent("manifest.json")

        let data = try Data(contentsOf: manifestURL)
        var manifest = try JSONDecoder().decode(PersistedSession.self, from: data)

        manifest = PersistedSession(
            id: manifest.id,
            name: manifest.name,
            createdAt: manifest.createdAt,
            updatedAt: Date(),
            state: manifest.state,
            deviceModel: manifest.deviceModel,
            appVersion: manifest.appVersion,
            meshChunkFiles: manifest.meshChunkFiles,
            pointCloudChunkFiles: manifest.pointCloudChunkFiles,
            textureFrameFiles: manifest.textureFrameFiles,
            worldMapFile: manifest.worldMapFile,
            trajectoryFile: manifest.trajectoryFile,
            coverageDataFile: fileName,
            scanDuration: manifest.scanDuration,
            totalVertices: manifest.totalVertices,
            totalFaces: manifest.totalFaces,
            areaScanned: manifest.areaScanned,
            thumbnailFile: manifest.thumbnailFile
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let updatedData = try encoder.encode(manifest)
        try updatedData.write(to: manifestURL)
    }

    private func serializeMatrix(_ matrix: simd_float4x4) -> Data {
        var m = matrix
        return Data(bytes: &m, count: MemoryLayout<simd_float4x4>.size)
    }

    private func deserializeMatrix(_ data: Data) -> simd_float4x4 {
        data.withUnsafeBytes { $0.load(as: simd_float4x4.self) }
    }

    private func serializeMatrix3x3(_ matrix: simd_float3x3) -> Data {
        var m = matrix
        return Data(bytes: &m, count: MemoryLayout<simd_float3x3>.size)
    }

    private func deserializeMatrix3x3(_ data: Data) -> simd_float3x3 {
        data.withUnsafeBytes { $0.load(as: simd_float3x3.self) }
    }

    private func serializeTrajectory(_ trajectory: [simd_float4x4]) -> Data {
        var data = Data()
        var count = UInt32(trajectory.count)
        data.append(Data(bytes: &count, count: 4))

        for var matrix in trajectory {
            data.append(Data(bytes: &matrix, count: MemoryLayout<simd_float4x4>.size))
        }

        return data
    }

    private func deserializeTrajectory(_ data: Data) -> [simd_float4x4] {
        var offset = 0
        let count = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
        offset += 4

        var trajectory: [simd_float4x4] = []
        trajectory.reserveCapacity(Int(count))

        for _ in 0..<count {
            let matrix = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: simd_float4x4.self) }
            trajectory.append(matrix)
            offset += MemoryLayout<simd_float4x4>.size
        }

        return trajectory
    }
}

// MARK: - Errors

enum PersistenceError: LocalizedError {
    case sessionNotFound
    case worldMapNotFound
    case invalidWorldMap
    case corruptedData
    case insufficientStorage
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Scan session not found"
        case .worldMapNotFound:
            return "AR World Map not found for this session"
        case .invalidWorldMap:
            return "Could not load AR World Map - it may be corrupted"
        case .corruptedData:
            return "Session data is corrupted"
        case .insufficientStorage:
            return "Not enough storage space available"
        case .permissionDenied:
            return "Permission denied to access storage"
        }
    }
}
