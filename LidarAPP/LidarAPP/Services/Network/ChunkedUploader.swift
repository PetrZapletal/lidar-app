import Foundation
import simd

/// Handles chunked upload of large files with resume capability
actor ChunkedUploader {

    // MARK: - Configuration

    struct Configuration {
        var chunkSize: Int = 5 * 1024 * 1024  // 5MB chunks
        var maxConcurrentChunks: Int = 3
        var maxRetries: Int = 3
        var retryDelay: TimeInterval = 2.0
        var timeout: TimeInterval = 60.0
    }

    // MARK: - Upload State

    enum UploadState: Equatable {
        case idle
        case preparing
        case uploading(progress: Float)
        case paused(progress: Float)
        case completed
        case failed(error: String)
    }

    // MARK: - Upload Task

    struct UploadTask: Identifiable {
        let id: UUID
        let scanId: String
        let fileURL: URL
        let totalSize: Int64
        var uploadedSize: Int64 = 0
        var uploadedChunks: Set<Int> = []
        var state: UploadState = .idle

        var progress: Float {
            guard totalSize > 0 else { return 0 }
            return Float(uploadedSize) / Float(totalSize)
        }
    }

    // MARK: - Chunk Info

    private struct ChunkInfo {
        let index: Int
        let offset: Int64
        let size: Int
        let data: Data
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let baseURL: URL
    private var authToken: String?

    private var currentTask: UploadTask?
    private var session: URLSession

    // Progress callback
    private var progressHandler: ((Float) -> Void)?
    private var completionHandler: ((Result<String, Error>) -> Void)?

    // MARK: - Initialization

    init(baseURL: URL, configuration: Configuration = Configuration()) {
        self.baseURL = baseURL
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.httpMaximumConnectionsPerHost = configuration.maxConcurrentChunks

        self.session = URLSession(configuration: sessionConfig, delegate: SelfSignedCertDelegate.shared, delegateQueue: nil)
    }

    init(configuration: Configuration = Configuration()) {
        self.baseURL = URL(string: "https://api.lidarapp.com/v1")!
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.httpMaximumConnectionsPerHost = configuration.maxConcurrentChunks

        self.session = URLSession(configuration: sessionConfig, delegate: SelfSignedCertDelegate.shared, delegateQueue: nil)
    }

    // MARK: - Authentication

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Upload Control

    func startUpload(
        fileURL: URL,
        scanId: String,
        onProgress: @escaping (Float) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    ) async throws {
        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw UploadError.invalidFile
        }

        // Create task
        let task = UploadTask(
            id: UUID(),
            scanId: scanId,
            fileURL: fileURL,
            totalSize: fileSize
        )

        self.currentTask = task
        self.progressHandler = onProgress
        self.completionHandler = onCompletion

        // Initialize upload session on server
        let uploadSession = try await initializeUpload(scanId: scanId, fileSize: fileSize)

        // Resume if there's existing progress
        if let existingChunks = uploadSession.uploadedChunks {
            self.currentTask?.uploadedChunks = Set(existingChunks)
            self.currentTask?.uploadedSize = Int64(existingChunks.count * configuration.chunkSize)
        }

        // Start uploading chunks
        try await uploadChunks()
    }

    func pauseUpload() {
        guard var task = currentTask else { return }
        task.state = .paused(progress: task.progress)
        currentTask = task
    }

    func resumeUpload() async throws {
        guard currentTask != nil else {
            throw UploadError.noActiveUpload
        }

        try await uploadChunks()
    }

    func cancelUpload() async throws {
        guard let task = currentTask else { return }

        // Notify server of cancellation
        try await cancelServerUpload(scanId: task.scanId)

        currentTask = nil
        progressHandler = nil
        completionHandler = nil
    }

    // MARK: - Upload Implementation

    private func initializeUpload(scanId: String, fileSize: Int64) async throws -> UploadSessionResponse {
        let url = baseURL.appendingPathComponent("scans/\(scanId)/upload/init")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = InitUploadRequest(
            fileSize: fileSize,
            chunkSize: configuration.chunkSize,
            contentType: "application/octet-stream"
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.serverError
        }

        return try JSONDecoder().decode(UploadSessionResponse.self, from: data)
    }

    private func uploadChunks() async throws {
        guard var task = currentTask else { return }

        task.state = .uploading(progress: task.progress)
        currentTask = task

        let fileHandle = try FileHandle(forReadingFrom: task.fileURL)
        defer { try? fileHandle.close() }

        let totalChunks = Int(ceil(Double(task.totalSize) / Double(configuration.chunkSize)))

        // Upload chunks that haven't been uploaded yet
        try await withThrowingTaskGroup(of: Int.self) { group in
            var chunksInFlight = 0

            for chunkIndex in 0..<totalChunks {
                // Skip already uploaded chunks
                if task.uploadedChunks.contains(chunkIndex) {
                    continue
                }

                // Check if paused
                if case .paused = currentTask?.state {
                    break
                }

                // Limit concurrent uploads
                while chunksInFlight >= configuration.maxConcurrentChunks {
                    if let completedChunk = try await group.next() {
                        chunksInFlight -= 1
                        self.currentTask?.uploadedChunks.insert(completedChunk)
                        self.currentTask?.uploadedSize += Int64(configuration.chunkSize)
                        self.progressHandler?(self.currentTask?.progress ?? 0)
                    }
                }

                // Read chunk data
                let offset = Int64(chunkIndex * configuration.chunkSize)
                try fileHandle.seek(toOffset: UInt64(offset))

                let chunkSize = min(configuration.chunkSize, Int(task.totalSize - offset))
                guard let chunkData = try fileHandle.read(upToCount: chunkSize) else {
                    continue
                }

                let chunk = ChunkInfo(
                    index: chunkIndex,
                    offset: offset,
                    size: chunkSize,
                    data: chunkData
                )

                group.addTask {
                    try await self.uploadChunk(chunk, scanId: task.scanId)
                    return chunkIndex
                }

                chunksInFlight += 1
            }

            // Wait for remaining chunks
            while let completedChunk = try await group.next() {
                self.currentTask?.uploadedChunks.insert(completedChunk)
                self.currentTask?.uploadedSize += Int64(configuration.chunkSize)
                self.progressHandler?(self.currentTask?.progress ?? 0)
            }
        }

        // Finalize upload
        if currentTask?.uploadedChunks.count == totalChunks {
            try await finalizeUpload(scanId: task.scanId)
            currentTask?.state = .completed
            completionHandler?(.success(task.scanId))
        }
    }

    private func uploadChunk(_ chunk: ChunkInfo, scanId: String) async throws {
        let url = baseURL.appendingPathComponent("scans/\(scanId)/upload/chunk")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(chunk.index)", forHTTPHeaderField: "X-Chunk-Index")
        request.setValue("\(chunk.offset)", forHTTPHeaderField: "X-Chunk-Offset")
        request.setValue("\(chunk.size)", forHTTPHeaderField: "X-Chunk-Size")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = chunk.data

        var lastError: Error?

        for attempt in 1...configuration.maxRetries {
            do {
                let (_, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw UploadError.chunkUploadFailed(chunk.index)
                }

                return  // Success
            } catch {
                lastError = error
                if attempt < configuration.maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? UploadError.chunkUploadFailed(chunk.index)
    }

    private func finalizeUpload(scanId: String) async throws {
        let url = baseURL.appendingPathComponent("scans/\(scanId)/upload/finalize")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.finalizationFailed
        }
    }

    private func cancelServerUpload(scanId: String) async throws {
        let url = baseURL.appendingPathComponent("scans/\(scanId)/upload/cancel")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        _ = try await session.data(for: request)
    }

    // MARK: - Status

    var uploadProgress: Float {
        currentTask?.progress ?? 0
    }

    var uploadState: UploadState {
        currentTask?.state ?? .idle
    }

    var isUploading: Bool {
        if case .uploading = currentTask?.state {
            return true
        }
        return false
    }
}

// MARK: - Error Types

enum UploadError: LocalizedError {
    case invalidFile
    case noActiveUpload
    case serverError
    case chunkUploadFailed(Int)
    case finalizationFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Invalid file"
        case .noActiveUpload: return "No active upload"
        case .serverError: return "Server error"
        case .chunkUploadFailed(let index): return "Chunk \(index) upload failed"
        case .finalizationFailed: return "Upload finalization failed"
        case .cancelled: return "Upload cancelled"
        }
    }
}

// MARK: - Request/Response Models

private struct InitUploadRequest: Encodable {
    let fileSize: Int64
    let chunkSize: Int
    let contentType: String
}

private struct UploadSessionResponse: Decodable {
    let uploadId: String
    let uploadedChunks: [Int]?
    let expiresAt: Date?
}

// MARK: - Data Preparation

extension ChunkedUploader {

    /// Prepare scan data for upload (combine point cloud, mesh, textures)
    static func prepareScanData(
        pointCloud: PointCloud?,
        meshData: MeshData?,
        textureFrames: [TextureFrame]?,
        outputURL: URL
    ) throws -> URL {
        // Create a ZIP archive or binary format containing all data

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        // Metadata
        var metadata: [String: Any] = [
            "version": "1.0",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        // Point cloud data
        if let pointCloud = pointCloud {
            metadata["pointCloudCount"] = pointCloud.points.count

            // Save point cloud as binary PLY
            let plyURL = outputURL.deletingLastPathComponent()
                .appendingPathComponent("pointcloud.ply")
            try exportToPLY(pointCloud: pointCloud, url: plyURL)
        }

        // Mesh data
        if let mesh = meshData {
            metadata["vertexCount"] = mesh.vertexCount
            metadata["faceCount"] = mesh.faceCount

            // Save mesh as binary
            let meshURL = outputURL.deletingLastPathComponent()
                .appendingPathComponent("mesh.bin")
            try exportMeshBinary(mesh: mesh, url: meshURL)
        }

        // Textures
        if let frames = textureFrames, !frames.isEmpty {
            metadata["textureCount"] = frames.count

            let texturesDir = outputURL.deletingLastPathComponent()
                .appendingPathComponent("textures")
            try FileManager.default.createDirectory(at: texturesDir, withIntermediateDirectories: true)

            for (index, frame) in frames.enumerated() {
                let textureURL = texturesDir.appendingPathComponent("frame_\(index).heic")
                try frame.imageData.write(to: textureURL)
            }
        }

        // Save metadata
        let metadataURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("metadata.json")
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        try metadataData.write(to: metadataURL)

        // TODO: Create ZIP archive of all files
        // For now, return the metadata URL
        return metadataURL
    }

    private static func exportToPLY(pointCloud: PointCloud, url: URL) throws {
        var plyContent = """
        ply
        format ascii 1.0
        element vertex \(pointCloud.points.count)
        property float x
        property float y
        property float z
        """

        if pointCloud.colors != nil {
            plyContent += """

            property uchar red
            property uchar green
            property uchar blue
            """
        }

        plyContent += """

        end_header

        """

        for (i, point) in pointCloud.points.enumerated() {
            var line = "\(point.x) \(point.y) \(point.z)"

            if let colors = pointCloud.colors, i < colors.count {
                let r = Int(colors[i].x * 255)
                let g = Int(colors[i].y * 255)
                let b = Int(colors[i].z * 255)
                line += " \(r) \(g) \(b)"
            }

            plyContent += line + "\n"
        }

        try plyContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func exportMeshBinary(mesh: MeshData, url: URL) throws {
        var data = Data()

        // Header
        var vertexCount = UInt32(mesh.vertexCount)
        var faceCount = UInt32(mesh.faceCount)
        data.append(Data(bytes: &vertexCount, count: 4))
        data.append(Data(bytes: &faceCount, count: 4))

        // Vertices
        for vertex in mesh.vertices {
            var v = vertex
            data.append(Data(bytes: &v, count: MemoryLayout<simd_float3>.size))
        }

        // Normals
        for normal in mesh.normals {
            var n = normal
            data.append(Data(bytes: &n, count: MemoryLayout<simd_float3>.size))
        }

        // Faces
        for face in mesh.faces {
            var f = face
            data.append(Data(bytes: &f, count: MemoryLayout<simd_uint3>.size))
        }

        try data.write(to: url)
    }
}
