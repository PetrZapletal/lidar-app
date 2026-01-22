import Foundation
import ARKit

// MARK: - Raw Data Uploader

/// Handles uploading raw scan data to debug backend
/// Supports chunked uploads for large files
actor RawDataUploader {

    // MARK: - Types

    enum UploadState: Sendable {
        case idle
        case preparing
        case uploading(progress: Float)
        case completed(scanId: String)
        case failed(message: String)
    }

    enum UploadError: Error, LocalizedError {
        case invalidConfiguration
        case backendUnreachable
        case preparationFailed(String)
        case uploadFailed(String)
        case serverError(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration:
                return "Invalid server configuration"
            case .backendUnreachable:
                return "Cannot connect to debug server - check Tailscale connection"
            case .preparationFailed(let msg):
                return "Failed to prepare data: \(msg)"
            case .uploadFailed(let msg):
                return "Upload failed: \(msg)"
            case .serverError(let code, let msg):
                return "Server error (\(code)): \(msg)"
            }
        }
    }

    struct UploadResult: Sendable {
        let scanId: String
        let uploadedBytes: Int64
        let durationSeconds: TimeInterval
        let meshAnchorCount: Int
        let textureFrameCount: Int
        let depthFrameCount: Int
    }

    // MARK: - Configuration

    struct Configuration: Sendable {
        let baseURL: URL
        let chunkSizeBytes: Int
        let maxConcurrentChunks: Int
        let timeoutSeconds: TimeInterval
        let maxRetries: Int

        init(
            baseURL: URL,
            chunkSizeBytes: Int = 5 * 1024 * 1024,
            maxConcurrentChunks: Int = 3,
            timeoutSeconds: TimeInterval = 60,
            maxRetries: Int = 3
        ) {
            self.baseURL = baseURL
            self.chunkSizeBytes = chunkSizeBytes
            self.maxConcurrentChunks = maxConcurrentChunks
            self.timeoutSeconds = timeoutSeconds
            self.maxRetries = maxRetries
        }

        @MainActor
        static func from(settings: DebugSettings) -> Configuration? {
            guard let baseURL = settings.rawDataBaseURL else {
                return nil
            }
            return Configuration(baseURL: baseURL)
        }
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let session: URLSession
    private(set) var state: UploadState = .idle

    // MARK: - Initialization

    init(configuration: Configuration) {
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeoutSeconds
        sessionConfig.timeoutIntervalForResource = configuration.timeoutSeconds * 10

        self.session = URLSession(configuration: sessionConfig, delegate: SelfSignedCertDelegate.shared, delegateQueue: nil)
    }

    /// Create uploader from settings (must be called from MainActor)
    @MainActor
    static func create(settings: DebugSettings) -> RawDataUploader? {
        guard let config = Configuration.from(settings: settings) else {
            return nil
        }
        return RawDataUploader(configuration: config)
    }

    // MARK: - Upload Raw Scan

    /// Upload complete raw scan data
    func uploadRawScan(
        meshAnchors: [ARMeshAnchor],
        textureFrames: [TextureFrame],
        depthFrames: [DepthFrame],
        sessionName: String,
        onProgress: @escaping @Sendable (Float) -> Void
    ) async throws -> UploadResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        state = .preparing

        // Check backend connectivity
        guard await checkBackendReachability() else {
            state = .failed(message: "Backend unreachable")
            throw UploadError.backendUnreachable
        }

        // Create scan on server
        let scanId = try await createScan(name: sessionName)

        // Package data to temp file
        let packageURL: URL
        do {
            // Create configuration from settings on main actor
            let config = await MainActor.run {
                RawDataPackager.PackageConfiguration.from(settings: DebugSettings.shared)
            }
            packageURL = try RawDataPackager.packageScan(
                meshAnchors: meshAnchors,
                textureFrames: textureFrames,
                depthFrames: depthFrames,
                configuration: config
            )
        } catch {
            state = .failed(message: "Packaging failed")
            throw UploadError.preparationFailed(error.localizedDescription)
        }

        defer {
            try? FileManager.default.removeItem(at: packageURL)
        }

        // Get file size
        let fileSize = try FileManager.default.attributesOfItem(atPath: packageURL.path)[.size] as! Int64

        state = .uploading(progress: 0)

        // Upload in chunks
        try await uploadFileInChunks(
            fileURL: packageURL,
            scanId: scanId,
            totalSize: fileSize,
            onProgress: { progress in
                Task { @MainActor in
                    onProgress(progress)
                }
            }
        )

        // Upload metadata
        try await uploadMetadata(
            scanId: scanId,
            sessionName: sessionName,
            meshAnchors: meshAnchors,
            textureFrames: textureFrames,
            depthFrames: depthFrames
        )

        // Finalize upload
        try await finalizeUpload(scanId: scanId)

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        let result = UploadResult(
            scanId: scanId,
            uploadedBytes: fileSize,
            durationSeconds: duration,
            meshAnchorCount: meshAnchors.count,
            textureFrameCount: textureFrames.count,
            depthFrameCount: depthFrames.count
        )

        state = .completed(scanId: scanId)
        return result
    }

    // MARK: - Private Methods

    private func checkBackendReachability() async -> Bool {
        let healthURL = configuration.baseURL.appendingPathComponent("/health")

        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }

    private func createScan(name: String) async throws -> String {
        let url = configuration.baseURL.appendingPathComponent("/api/v1/debug/scans/raw/init")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": name,
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "device_model": getDeviceModel(),
            "ios_version": UIDevice.current.systemVersion
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.uploadFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UploadError.serverError(httpResponse.statusCode, message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scanId = json["scan_id"] as? String else {
            throw UploadError.uploadFailed("Invalid response format")
        }

        return scanId
    }

    private func uploadFileInChunks(
        fileURL: URL,
        scanId: String,
        totalSize: Int64,
        onProgress: @escaping (Float) -> Void
    ) async throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let chunkSize = configuration.chunkSizeBytes
        var chunkIndex = 0
        var uploadedBytes: Int64 = 0

        while true {
            let chunkData = try handle.read(upToCount: chunkSize)
            guard let data = chunkData, !data.isEmpty else {
                break
            }

            let isLastChunk = (uploadedBytes + Int64(data.count)) >= totalSize || data.count < chunkSize
            try await uploadChunk(
                data: data,
                scanId: scanId,
                chunkIndex: chunkIndex,
                isLast: isLastChunk
            )

            uploadedBytes += Int64(data.count)
            chunkIndex += 1

            let progress = Float(uploadedBytes) / Float(totalSize)
            state = .uploading(progress: progress)
            onProgress(progress)
        }
    }

    private func uploadChunk(
        data: Data,
        scanId: String,
        chunkIndex: Int,
        isLast: Bool
    ) async throws {
        let url = configuration.baseURL
            .appendingPathComponent("/api/v1/debug/scans/\(scanId)/raw/chunk")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(chunkIndex)", forHTTPHeaderField: "X-Chunk-Index")
        request.setValue(isLast ? "true" : "false", forHTTPHeaderField: "X-Is-Last-Chunk")
        request.httpBody = data

        var lastError: Error?

        for attempt in 0..<configuration.maxRetries {
            do {
                let (responseData, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw UploadError.uploadFailed("Invalid response")
                }

                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    return // Success
                }

                let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
                throw UploadError.serverError(httpResponse.statusCode, message)

            } catch {
                lastError = error

                // Wait before retry with exponential backoff
                if attempt < configuration.maxRetries - 1 {
                    try await Task.sleep(nanoseconds: UInt64((1 << attempt) * 1_000_000_000))
                }
            }
        }

        throw lastError ?? UploadError.uploadFailed("Max retries exceeded")
    }

    private func uploadMetadata(
        scanId: String,
        sessionName: String,
        meshAnchors: [ARMeshAnchor],
        textureFrames: [TextureFrame],
        depthFrames: [DepthFrame]
    ) async throws {
        let url = configuration.baseURL
            .appendingPathComponent("/api/v1/debug/scans/\(scanId)/metadata")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let deviceInfo: [String: String] = [
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "device_model": getDeviceModel(),
            "ios_version": UIDevice.current.systemVersion,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]

        guard let metadataData = RawDataPackager.generateMetadata(
            scanId: UUID(uuidString: scanId) ?? UUID(),
            sessionName: sessionName,
            meshAnchors: meshAnchors,
            textureFrames: textureFrames,
            depthFrames: depthFrames,
            deviceInfo: deviceInfo
        ) else {
            throw UploadError.preparationFailed("Failed to generate metadata")
        }

        request.httpBody = metadataData

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw UploadError.uploadFailed("Failed to upload metadata")
        }
    }

    private func finalizeUpload(scanId: String) async throws {
        let url = configuration.baseURL
            .appendingPathComponent("/api/v1/debug/scans/\(scanId)/raw/finalize")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.uploadFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UploadError.serverError(httpResponse.statusCode, message)
        }
    }

    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

// MARK: - Upload Progress View Model

@MainActor
@Observable
final class RawDataUploadViewModel {
    var isUploading = false
    var progress: Float = 0
    var statusMessage = ""
    var lastResult: RawDataUploader.UploadResult?
    var lastError: Error?

    private var uploader: RawDataUploader?

    func upload(
        meshAnchors: [ARMeshAnchor],
        textureFrames: [TextureFrame],
        depthFrames: [DepthFrame],
        sessionName: String
    ) async {
        guard let uploader = RawDataUploader.create(settings: DebugSettings.shared) else {
            lastError = RawDataUploader.UploadError.invalidConfiguration
            statusMessage = "Invalid configuration"
            return
        }

        self.uploader = uploader
        isUploading = true
        progress = 0
        statusMessage = "Preparing..."
        lastError = nil

        do {
            let result = try await uploader.uploadRawScan(
                meshAnchors: meshAnchors,
                textureFrames: textureFrames,
                depthFrames: depthFrames,
                sessionName: sessionName,
                onProgress: { [weak self] (p: Float) in
                    Task { @MainActor in
                        self?.progress = p
                        self?.statusMessage = "Uploading: \(Int(p * 100))%"
                    }
                }
            )

            lastResult = result
            statusMessage = "Upload complete: \(result.scanId)"

        } catch {
            lastError = error
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isUploading = false
    }
}
