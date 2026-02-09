import Foundation
import Combine
import UIKit

// MARK: - Processing Status

/// Represents the current status of a cloud-side scan processing job.
struct ProcessingStatus: Codable {
    let scanId: String
    let status: String  // "pending", "processing", "completed", "failed"
    let progress: Float?
    let stage: String?
    let resultUrl: String?
    let error: String?

    /// Whether the processing has reached a terminal state.
    var isTerminal: Bool {
        status == "completed" || status == "failed"
    }

    /// Whether the processing completed successfully.
    var isCompleted: Bool {
        status == "completed"
    }

    /// Whether the processing has failed.
    var isFailed: Bool {
        status == "failed"
    }
}

// MARK: - Cloud Processing Service

/// Orchestrates the full cloud scan processing pipeline:
/// upload -> process -> poll/stream status -> download result.
/// Tracks progress through each stage and exposes state for UI binding.
@MainActor
@Observable
final class CloudProcessingService {

    // MARK: - Processing State

    enum ProcessingState: Equatable {
        case idle
        case uploading(progress: Float)
        case processing(progress: Float, stage: String)
        case downloading(progress: Float)
        case completed(resultURL: URL)
        case failed(String)

        static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.uploading(let a), .uploading(let b)): return a == b
            case (.processing(let a1, let a2), .processing(let b1, let b2)): return a1 == b1 && a2 == b2
            case (.downloading(let a), .downloading(let b)): return a == b
            case (.completed(let a), .completed(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - Constants

    private enum Constants {
        static let pollIntervalSeconds: TimeInterval = 2.0
        static let processingTimeoutSeconds: TimeInterval = 600.0  // 10 minutes
        static let defaultFormat = "glb"
    }

    // MARK: - Properties

    private(set) var state: ProcessingState = .idle

    private let services: ServiceContainer
    private let webSocketService: WebSocketService
    private var statusSubscription: AnyCancellable?
    private var processingTask: Task<URL, Error>?

    // MARK: - Initialization

    init(services: ServiceContainer) {
        self.services = services
        self.webSocketService = WebSocketService()
    }

    // MARK: - Full Pipeline

    /// Execute the complete cloud processing pipeline for a scan session.
    /// 1. Exports the scan to a file
    /// 2. Creates a scan record on the server
    /// 3. Uploads the scan file
    /// 4. Starts AI processing
    /// 5. Polls for completion (with WebSocket fallback)
    /// 6. Downloads the processed result
    ///
    /// - Parameters:
    ///   - scanSession: The scan session to process.
    ///   - format: The desired output format (default: "glb").
    /// - Returns: The local URL of the downloaded processed result.
    func processInCloud(scanSession: ScanSession, format: String = "glb") async throws -> URL {
        // Cancel any existing processing
        processingTask?.cancel()
        state = .idle

        let task = Task<URL, Error> { [weak self] in
            guard let self = self else {
                throw NetworkError.notConnected
            }

            // Step 1: Create scan on server
            infoLog("Cloud processing: creating scan record", category: .logCategoryNetwork)
            let scanId = try await self.createScan(name: scanSession.name)
            debugLog("Cloud processing: scan created with ID \(scanId)", category: .logCategoryNetwork)

            // Step 2: Export scan to temporary file for upload
            infoLog("Cloud processing: exporting scan for upload", category: .logCategoryNetwork)
            let exportURL = try await self.exportScanForUpload(scanSession: scanSession)
            defer {
                try? FileManager.default.removeItem(at: exportURL)
            }

            // Step 3: Upload
            try Task.checkCancellation()
            infoLog("Cloud processing: uploading scan \(scanId)", category: .logCategoryNetwork)
            try await self.uploadScan(scanId: scanId, fileURL: exportURL) { [weak self] progress in
                Task { @MainActor in
                    self?.state = .uploading(progress: progress)
                }
            }

            // Step 4: Start processing
            try Task.checkCancellation()
            infoLog("Cloud processing: starting AI processing for scan \(scanId)", category: .logCategoryNetwork)
            let taskId = try await self.startProcessing(scanId: scanId, format: format)
            debugLog("Cloud processing: task started with ID \(taskId)", category: .logCategoryNetwork)

            await MainActor.run {
                self.state = .processing(progress: 0, stage: "Initializing")
            }

            // Step 5: Connect WebSocket for real-time updates and poll for status
            try Task.checkCancellation()
            try await self.waitForCompletion(scanId: scanId)

            // Step 6: Download result
            try Task.checkCancellation()
            infoLog("Cloud processing: downloading result for scan \(scanId)", category: .logCategoryNetwork)
            let resultURL = try await self.downloadResult(scanId: scanId, format: format) { [weak self] progress in
                Task { @MainActor in
                    self?.state = .downloading(progress: progress)
                }
            }

            await MainActor.run {
                self.state = .completed(resultURL: resultURL)
            }

            infoLog("Cloud processing: completed for scan \(scanId), result at \(resultURL.lastPathComponent)", category: .logCategoryNetwork)
            return resultURL
        }

        processingTask = task

        do {
            let result = try await task.value
            return result
        } catch is CancellationError {
            state = .failed("Processing cancelled")
            throw CancellationError()
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Cancel the current cloud processing pipeline.
    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        webSocketService.disconnect()
        statusSubscription?.cancel()
        statusSubscription = nil
        state = .idle
        infoLog("Cloud processing cancelled by user", category: .logCategoryNetwork)
    }

    // MARK: - Individual Pipeline Steps

    /// Create a new scan record on the server.
    /// - Parameter name: The scan name.
    /// - Returns: The server-assigned scan ID.
    func createScan(name: String) async throws -> String {
        struct CreateScanRequest: Encodable {
            let name: String
            let deviceModel: String
            let appVersion: String
        }

        struct CreateScanResponse: Decodable {
            let scanId: String
        }

        let body = CreateScanRequest(
            name: name,
            deviceModel: UIDevice.current.modelIdentifier,
            appVersion: Bundle.main.appVersion
        )

        let response: CreateScanResponse = try await services.network.request(
            endpoint: "/api/v1/scans",
            method: .post,
            body: body
        )

        return response.scanId
    }

    /// Upload a scan file to the server.
    /// - Parameters:
    ///   - scanId: The server scan ID.
    ///   - fileURL: Local URL of the file to upload.
    ///   - onProgress: Progress callback (0.0 to 1.0).
    func uploadScan(
        scanId: String,
        fileURL: URL,
        onProgress: @escaping (Float) -> Void
    ) async throws {
        state = .uploading(progress: 0)

        let _ = try await services.network.uploadFile(
            endpoint: "/api/v1/scans/\(scanId)/upload",
            fileURL: fileURL,
            onProgress: { progress in
                onProgress(progress)
            }
        )

        debugLog("Scan \(scanId) uploaded successfully", category: .logCategoryNetwork)
    }

    /// Start AI processing for an uploaded scan.
    /// - Parameters:
    ///   - scanId: The server scan ID.
    ///   - format: The desired output format.
    /// - Returns: The processing task ID.
    func startProcessing(scanId: String, format: String = "glb") async throws -> String {
        struct ProcessRequest: Encodable {
            let format: String
        }

        struct ProcessResponse: Decodable {
            let taskId: String
        }

        let body = ProcessRequest(format: format)

        let response: ProcessResponse = try await services.network.request(
            endpoint: "/api/v1/scans/\(scanId)/process",
            method: .post,
            body: body
        )

        return response.taskId
    }

    /// Poll the server for the current processing status.
    /// - Parameter scanId: The server scan ID.
    /// - Returns: The current processing status.
    func pollStatus(scanId: String) async throws -> ProcessingStatus {
        let status: ProcessingStatus = try await services.network.request(
            endpoint: "/api/v1/scans/\(scanId)/status",
            method: .get,
            body: nil
        )
        return status
    }

    /// Download the processed result from the server.
    /// - Parameters:
    ///   - scanId: The server scan ID.
    ///   - format: The output format.
    ///   - onProgress: Progress callback (0.0 to 1.0).
    /// - Returns: The local URL of the downloaded file.
    func downloadResult(
        scanId: String,
        format: String = "glb",
        onProgress: @escaping (Float) -> Void
    ) async throws -> URL {
        state = .downloading(progress: 0)

        let downloadsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudProcessing", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let destinationURL = downloadsDir
            .appendingPathComponent("\(scanId).\(format)")

        try await services.network.downloadFile(
            endpoint: "/api/v1/scans/\(scanId)/result",
            destinationURL: destinationURL,
            onProgress: { progress in
                onProgress(progress)
            }
        )

        debugLog("Result downloaded for scan \(scanId): \(destinationURL.lastPathComponent)", category: .logCategoryNetwork)
        return destinationURL
    }

    // MARK: - Private: Wait for Processing Completion

    /// Wait for server-side processing to complete by combining WebSocket updates with HTTP polling.
    /// WebSocket provides real-time updates; polling acts as a fallback guarantee.
    private func waitForCompletion(scanId: String) async throws {
        // Subscribe to WebSocket updates
        await webSocketService.connect(scanId: scanId)

        statusSubscription = webSocketService.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self = self else { return }
                self.handleWebSocketStatusUpdate(message)
            }

        defer {
            webSocketService.disconnect()
            statusSubscription?.cancel()
            statusSubscription = nil
        }

        // Poll with timeout
        let deadline = Date().addingTimeInterval(Constants.processingTimeoutSeconds)

        while Date() < deadline {
            try Task.checkCancellation()

            let status = try await pollStatus(scanId: scanId)

            // Update state from polling
            if let progress = status.progress {
                let stage = status.stage ?? "Processing"
                state = .processing(progress: progress, stage: stage)
            }

            if status.isCompleted {
                debugLog("Cloud processing completed for scan \(scanId)", category: .logCategoryNetwork)
                return
            }

            if status.isFailed {
                let errorMessage = status.error ?? "Unknown processing error"
                errorLog("Cloud processing failed for scan \(scanId): \(errorMessage)", category: .logCategoryNetwork)
                throw NetworkError.requestFailed(statusCode: 0, message: "Processing failed: \(errorMessage)")
            }

            // Wait before next poll
            try await Task.sleep(nanoseconds: UInt64(Constants.pollIntervalSeconds * 1_000_000_000))
        }

        // Timeout reached
        errorLog("Cloud processing timed out for scan \(scanId) after \(Int(Constants.processingTimeoutSeconds))s", category: .logCategoryNetwork)
        throw NetworkError.timeout
    }

    /// Handle real-time status updates received via WebSocket.
    private func handleWebSocketStatusUpdate(_ message: WebSocketMessage) {
        switch message.type {
        case "processing_update":
            let progress = message.data?["progress"]?.floatValue ?? 0
            let stage = message.data?["stage"]?.stringValue ?? "Processing"
            state = .processing(progress: progress, stage: stage)
            debugLog("WebSocket processing update: \(stage) (\(Int(progress * 100))%)", category: .logCategoryNetwork)

        case "processing_completed":
            debugLog("WebSocket: processing completed", category: .logCategoryNetwork)

        case "processing_failed":
            let error = message.data?["error"]?.stringValue ?? "Unknown error"
            errorLog("WebSocket: processing failed - \(error)", category: .logCategoryNetwork)

        case "pong", "ping":
            // Keepalive messages, no action needed
            break

        default:
            debugLog("WebSocket received unhandled message type: \(message.type)", category: .logCategoryNetwork)
        }
    }

    // MARK: - Private: Scan Export

    /// Export the scan session data to a temporary file suitable for upload.
    private func exportScanForUpload(scanSession: ScanSession) async throws -> URL {
        // If we have mesh data, combine and export as PLY via ExportService
        if let unifiedMesh = scanSession.combinedMesh.toUnifiedMesh() {
            let exportURL = try await services.export.export(
                meshData: unifiedMesh,
                format: .ply,
                name: "cloud_upload_\(scanSession.id.uuidString.prefix(8))"
            )
            return exportURL
        }

        // If we have point cloud data, export as point cloud PLY
        if let pointCloud = scanSession.pointCloud {
            let exportURL = try await services.export.exportPointCloud(
                pointCloud,
                name: "cloud_upload_\(scanSession.id.uuidString.prefix(8))"
            )
            return exportURL
        }

        throw NetworkError.uploadFailed("No mesh or point cloud data available for upload")
    }
}
