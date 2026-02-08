import Foundation
import simd
import Compression

/// Manages streaming mesh/point cloud data to disk in chunks
/// Prevents memory overflow during large space scanning
actor ChunkManager {

    // MARK: - Configuration

    struct Configuration {
        var chunkSizeVertices: Int = 50_000
        var chunkSizeFaces: Int = 30_000
        var maxInMemoryChunks: Int = 5
        var compressionEnabled: Bool = true
        var flushThresholdBytes: Int = 50_000_000 // 50MB

        static let `default` = Configuration()
    }

    // MARK: - Chunk Metadata

    struct ChunkMetadata: Codable, Identifiable, Sendable {
        let id: UUID
        let index: Int
        let vertexCount: Int
        let faceCount: Int
        let boundingBox: CodableBoundingBox
        let fileName: String
        let fileSizeBytes: Int
        let createdAt: Date
        let isCompressed: Bool
    }

    // MARK: - Properties

    private let baseDirectory: URL
    private let configuration: Configuration

    private var loadedChunks: [UUID: MeshData] = [:]
    private var chunkAccessOrder: [UUID] = [] // For LRU eviction
    private var allMetadata: [ChunkMetadata] = []
    private var currentChunkIndex: Int = 0

    // Statistics
    private(set) var totalBytesOnDisk: Int = 0
    private(set) var totalChunksWritten: Int = 0

    // MARK: - Initialization

    init(sessionId: UUID, configuration: Configuration = .default) throws {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.baseDirectory = documentsDir.appendingPathComponent("ScanChunks/\(sessionId.uuidString)")
        self.configuration = configuration

        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    init(baseDirectory: URL, configuration: Configuration = .default) throws {
        self.baseDirectory = baseDirectory
        self.configuration = configuration

        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Write Operations

    /// Write mesh data as a new chunk to disk
    func writeChunk(_ meshData: MeshData) async throws -> ChunkMetadata {
        let chunkId = meshData.id
        let fileName = "chunk_\(currentChunkIndex)_\(chunkId.uuidString).bin"
        let fileURL = baseDirectory.appendingPathComponent(fileName)

        // Serialize mesh data to binary
        var data = Data()

        // Header: vertex count, face count
        var vertexCount = UInt32(meshData.vertices.count)
        var faceCount = UInt32(meshData.faces.count)
        data.append(Data(bytes: &vertexCount, count: 4))
        data.append(Data(bytes: &faceCount, count: 4))

        // Transform matrix (16 floats)
        var transform = meshData.transform
        data.append(Data(bytes: &transform, count: MemoryLayout<simd_float4x4>.size))

        // Vertices (3 floats each)
        for var vertex in meshData.vertices {
            data.append(Data(bytes: &vertex, count: MemoryLayout<simd_float3>.size))
        }

        // Normals (3 floats each)
        for var normal in meshData.normals {
            data.append(Data(bytes: &normal, count: MemoryLayout<simd_float3>.size))
        }

        // Faces (3 uint32 each)
        for var face in meshData.faces {
            data.append(Data(bytes: &face, count: MemoryLayout<simd_uint3>.size))
        }

        // Optionally compress
        var finalData = data
        var isCompressed = false

        if configuration.compressionEnabled {
            if let compressed = compressData(data) {
                finalData = compressed
                isCompressed = true
            }
        }

        // Write to disk
        try finalData.write(to: fileURL)

        // Calculate bounding box
        let boundingBox = calculateBoundingBox(from: meshData.vertices)

        // Create metadata
        let metadata = ChunkMetadata(
            id: chunkId,
            index: currentChunkIndex,
            vertexCount: meshData.vertices.count,
            faceCount: meshData.faces.count,
            boundingBox: boundingBox,
            fileName: fileName,
            fileSizeBytes: finalData.count,
            createdAt: Date(),
            isCompressed: isCompressed
        )

        allMetadata.append(metadata)
        currentChunkIndex += 1
        totalBytesOnDisk += finalData.count
        totalChunksWritten += 1

        return metadata
    }

    /// Write point cloud data as a chunk
    func writePointCloudChunk(points: [simd_float3], colors: [simd_float4]?) async throws -> ChunkMetadata {
        let chunkId = UUID()
        let fileName = "pointcloud_\(currentChunkIndex)_\(chunkId.uuidString).bin"
        let fileURL = baseDirectory.appendingPathComponent(fileName)

        var data = Data()

        // Header: point count, has colors flag
        var pointCount = UInt32(points.count)
        var hasColors: UInt8 = colors != nil ? 1 : 0
        data.append(Data(bytes: &pointCount, count: 4))
        data.append(Data(bytes: &hasColors, count: 1))

        // Points
        for var point in points {
            data.append(Data(bytes: &point, count: MemoryLayout<simd_float3>.size))
        }

        // Colors (if present)
        if let colors = colors {
            for var color in colors {
                data.append(Data(bytes: &color, count: MemoryLayout<simd_float4>.size))
            }
        }

        // Compress
        var finalData = data
        var isCompressed = false

        if configuration.compressionEnabled {
            if let compressed = compressData(data) {
                finalData = compressed
                isCompressed = true
            }
        }

        try finalData.write(to: fileURL)

        let boundingBox = calculateBoundingBox(from: points)

        let metadata = ChunkMetadata(
            id: chunkId,
            index: currentChunkIndex,
            vertexCount: points.count,
            faceCount: 0,
            boundingBox: boundingBox,
            fileName: fileName,
            fileSizeBytes: finalData.count,
            createdAt: Date(),
            isCompressed: isCompressed
        )

        allMetadata.append(metadata)
        currentChunkIndex += 1
        totalBytesOnDisk += finalData.count
        totalChunksWritten += 1

        return metadata
    }

    // MARK: - Read Operations

    /// Load a chunk from disk (with LRU caching)
    func loadChunk(id: UUID) async throws -> MeshData {
        // Check cache first
        if let cached = loadedChunks[id] {
            // Move to end of access order (most recently used)
            chunkAccessOrder.removeAll { $0 == id }
            chunkAccessOrder.append(id)
            return cached
        }

        // Find metadata
        guard let metadata = allMetadata.first(where: { $0.id == id }) else {
            throw ChunkError.chunkNotFound(id)
        }

        // Load from disk
        let fileURL = baseDirectory.appendingPathComponent(metadata.fileName)
        var data = try Data(contentsOf: fileURL)

        // Decompress if needed
        if metadata.isCompressed {
            guard let decompressed = decompressData(data) else {
                throw ChunkError.decompressionFailed
            }
            data = decompressed
        }

        // Parse binary data
        let meshData = try parseMeshData(from: data, id: id)

        // Cache with LRU eviction
        await cacheChunk(id: id, data: meshData)

        return meshData
    }

    /// Load point cloud chunk from disk
    func loadPointCloudChunk(id: UUID) async throws -> (points: [simd_float3], colors: [simd_float4]?) {
        guard let metadata = allMetadata.first(where: { $0.id == id }) else {
            throw ChunkError.chunkNotFound(id)
        }

        let fileURL = baseDirectory.appendingPathComponent(metadata.fileName)
        var data = try Data(contentsOf: fileURL)

        if metadata.isCompressed {
            guard let decompressed = decompressData(data) else {
                throw ChunkError.decompressionFailed
            }
            data = decompressed
        }

        return try parsePointCloudData(from: data)
    }

    // MARK: - Cache Management

    private func cacheChunk(id: UUID, data: MeshData) async {
        // Evict if at capacity
        while loadedChunks.count >= configuration.maxInMemoryChunks {
            await evictOldestChunk()
        }

        loadedChunks[id] = data
        chunkAccessOrder.append(id)
    }

    private func evictOldestChunk() async {
        guard let oldestId = chunkAccessOrder.first else { return }
        chunkAccessOrder.removeFirst()
        loadedChunks.removeValue(forKey: oldestId)
    }

    /// Evict chunks to free memory
    func evictOldestChunks(keepCount: Int) async {
        while loadedChunks.count > keepCount {
            await evictOldestChunk()
        }
    }

    /// Clear all cached chunks from memory
    func clearCache() {
        loadedChunks.removeAll()
        chunkAccessOrder.removeAll()
    }

    // MARK: - Metadata Access

    /// Get all chunk metadata
    func getAllMetadata() -> [ChunkMetadata] {
        return allMetadata
    }

    /// Get chunk IDs for a region
    func getChunksInRegion(minBound: simd_float3, maxBound: simd_float3) -> [UUID] {
        return allMetadata.filter { metadata in
            // Check if bounding boxes overlap
            let chunkMin = simd_float3(metadata.boundingBox.minX, metadata.boundingBox.minY, metadata.boundingBox.minZ)
            let chunkMax = simd_float3(metadata.boundingBox.maxX, metadata.boundingBox.maxY, metadata.boundingBox.maxZ)

            return !(chunkMax.x < minBound.x || chunkMin.x > maxBound.x ||
                    chunkMax.y < minBound.y || chunkMin.y > maxBound.y ||
                    chunkMax.z < minBound.z || chunkMin.z > maxBound.z)
        }.map { $0.id }
    }

    // MARK: - Combine Operations

    /// Combine multiple chunks into unified mesh
    func combineChunks(ids: [UUID]) async throws -> MeshData {
        var allVertices: [simd_float3] = []
        var allNormals: [simd_float3] = []
        var allFaces: [simd_uint3] = []
        var vertexOffset: UInt32 = 0

        for id in ids {
            let chunk = try await loadChunk(id: id)

            allVertices.append(contentsOf: chunk.vertices)
            allNormals.append(contentsOf: chunk.normals)

            // Offset face indices
            let offsetFaces = chunk.faces.map { face in
                simd_uint3(
                    face.x + vertexOffset,
                    face.y + vertexOffset,
                    face.z + vertexOffset
                )
            }
            allFaces.append(contentsOf: offsetFaces)

            vertexOffset += UInt32(chunk.vertices.count)
        }

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: allVertices,
            normals: allNormals,
            faces: allFaces
        )
    }

    // MARK: - Persistence

    /// Save metadata index to disk
    func saveMetadataIndex() throws {
        let indexURL = baseDirectory.appendingPathComponent("chunk_index.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(allMetadata)
        try data.write(to: indexURL)
    }

    /// Load metadata index from disk
    func loadMetadataIndex() throws {
        let indexURL = baseDirectory.appendingPathComponent("chunk_index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }

        let data = try Data(contentsOf: indexURL)
        allMetadata = try JSONDecoder().decode([ChunkMetadata].self, from: data)

        // Update counters
        currentChunkIndex = (allMetadata.map { $0.index }.max() ?? -1) + 1
        totalChunksWritten = allMetadata.count
        totalBytesOnDisk = allMetadata.reduce(0) { $0 + $1.fileSizeBytes }
    }

    /// Delete all chunks for this session
    func deleteAllChunks() throws {
        try FileManager.default.removeItem(at: baseDirectory)
        allMetadata.removeAll()
        loadedChunks.removeAll()
        chunkAccessOrder.removeAll()
        currentChunkIndex = 0
        totalBytesOnDisk = 0
        totalChunksWritten = 0
    }

    // MARK: - Private Helpers

    private func calculateBoundingBox(from vertices: [simd_float3]) -> CodableBoundingBox {
        guard !vertices.isEmpty else {
            return CodableBoundingBox(minX: 0, minY: 0, minZ: 0, maxX: 0, maxY: 0, maxZ: 0)
        }

        var minPoint = vertices[0]
        var maxPoint = vertices[0]

        for vertex in vertices {
            minPoint = simd_min(minPoint, vertex)
            maxPoint = simd_max(maxPoint, vertex)
        }

        return CodableBoundingBox(
            minX: minPoint.x, minY: minPoint.y, minZ: minPoint.z,
            maxX: maxPoint.x, maxY: maxPoint.y, maxZ: maxPoint.z
        )
    }

    private func parseMeshData(from data: Data, id: UUID) throws -> MeshData {
        var offset = 0

        // Read header
        let vertexCount = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
        offset += 4
        let faceCount = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
        offset += 4

        // Read transform
        let transform = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: simd_float4x4.self) }
        offset += MemoryLayout<simd_float4x4>.size

        // Read vertices
        var vertices: [simd_float3] = []
        vertices.reserveCapacity(Int(vertexCount))
        for _ in 0..<vertexCount {
            let vertex = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: simd_float3.self) }
            vertices.append(vertex)
            offset += MemoryLayout<simd_float3>.size
        }

        // Read normals
        var normals: [simd_float3] = []
        normals.reserveCapacity(Int(vertexCount))
        for _ in 0..<vertexCount {
            let normal = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: simd_float3.self) }
            normals.append(normal)
            offset += MemoryLayout<simd_float3>.size
        }

        // Read faces
        var faces: [simd_uint3] = []
        faces.reserveCapacity(Int(faceCount))
        for _ in 0..<faceCount {
            let face = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: simd_uint3.self) }
            faces.append(face)
            offset += MemoryLayout<simd_uint3>.size
        }

        return MeshData(
            id: id,
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces,
            transform: transform
        )
    }

    private func parsePointCloudData(from data: Data) throws -> (points: [simd_float3], colors: [simd_float4]?) {
        var offset = 0

        let pointCount = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
        offset += 4
        let hasColors = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt8.self) } == 1
        offset += 1

        var points: [simd_float3] = []
        points.reserveCapacity(Int(pointCount))
        for _ in 0..<pointCount {
            let point = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: simd_float3.self) }
            points.append(point)
            offset += MemoryLayout<simd_float3>.size
        }

        var colors: [simd_float4]?
        if hasColors {
            colors = []
            colors?.reserveCapacity(Int(pointCount))
            for _ in 0..<pointCount {
                let color = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: simd_float4.self) }
                colors?.append(color)
                offset += MemoryLayout<simd_float4>.size
            }
        }

        return (points, colors)
    }

    // MARK: - Compression

    private func compressData(_ data: Data) -> Data? {
        let sourceSize = data.count
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_encode_buffer(
                destinationBuffer,
                sourceSize,
                sourcePtr,
                sourceSize,
                nil,
                COMPRESSION_LZFSE
            )
        }

        guard compressedSize > 0 && compressedSize < sourceSize else {
            return nil // Compression didn't help
        }

        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    private func decompressData(_ data: Data) -> Data? {
        // Estimate decompressed size (4x compressed size as initial guess)
        var destinationSize = data.count * 4
        var destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)

        let decompressedSize = data.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }

            var result = compression_decode_buffer(
                destinationBuffer,
                destinationSize,
                sourcePtr,
                data.count,
                nil,
                COMPRESSION_LZFSE
            )

            // If buffer was too small, try with larger buffer
            if result == 0 {
                destinationBuffer.deallocate()
                destinationSize = data.count * 16
                destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)

                result = compression_decode_buffer(
                    destinationBuffer,
                    destinationSize,
                    sourcePtr,
                    data.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }

            return result
        }

        defer { destinationBuffer.deallocate() }

        guard decompressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
}

// MARK: - Supporting Types

struct CodableBoundingBox: Codable, Sendable {
    let minX: Float
    let minY: Float
    let minZ: Float
    let maxX: Float
    let maxY: Float
    let maxZ: Float

    var min: simd_float3 { simd_float3(minX, minY, minZ) }
    var max: simd_float3 { simd_float3(maxX, maxY, maxZ) }
    var center: simd_float3 { (min + max) / 2 }
    var size: simd_float3 { max - min }
}

extension CodableBoundingBox {
    init(from boundingBox: BoundingBox) {
        self.minX = boundingBox.min.x
        self.minY = boundingBox.min.y
        self.minZ = boundingBox.min.z
        self.maxX = boundingBox.max.x
        self.maxY = boundingBox.max.y
        self.maxZ = boundingBox.max.z
    }
}

enum ChunkError: LocalizedError {
    case chunkNotFound(UUID)
    case decompressionFailed
    case invalidData
    case diskFull

    var errorDescription: String? {
        switch self {
        case .chunkNotFound(let id):
            return "Chunk not found: \(id)"
        case .decompressionFailed:
            return "Failed to decompress chunk data"
        case .invalidData:
            return "Invalid chunk data format"
        case .diskFull:
            return "Not enough disk space to save chunk"
        }
    }
}
