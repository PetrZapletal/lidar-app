import Foundation
import ARKit
import UIKit

/// Processing state for a scan
enum ScanProcessingState: Equatable {
    case idle
    case scanning(progress: Float)
    case processing(stage: ProcessingStage, progress: Float)
    case uploading(progress: Float)
    case serverProcessing(stage: String, progress: Float)
    case downloading(progress: Float)
    case completed(localURL: URL)
    case failed(error: String)

    var isActive: Bool {
        switch self {
        case .idle, .completed, .failed:
            return false
        default:
            return true
        }
    }
}

/// Processing stage on device
enum ProcessingStage: String, CaseIterable {
    case depthFusion = "depth_fusion"
    case pointCloudExtraction = "point_cloud"
    case meshGeneration = "mesh_generation"
    case dataPreparation = "data_preparation"

    var displayName: String {
        switch self {
        case .depthFusion: return "Fúze hloubky"
        case .pointCloudExtraction: return "Extrakce point cloudu"
        case .meshGeneration: return "Generování mesh"
        case .dataPreparation: return "Příprava dat"
        }
    }

    var weight: Float {
        switch self {
        case .depthFusion: return 0.3
        case .pointCloudExtraction: return 0.3
        case .meshGeneration: return 0.2
        case .dataPreparation: return 0.2
        }
    }
}

/// Scan processing configuration
struct ProcessingConfiguration {
    var enableDepthFusion: Bool = true
    var enableMeshCorrection: Bool = true
    var targetPointCount: Int = 500_000
    var outputFormats: [String] = ["usdz", "gltf"]
    var meshResolution: String = "high"
    var textureResolution: Int = 4096
}

/// Result of local processing
struct LocalProcessingResult {
    let pointCloud: PointCloud
    let mesh: MeshData?
    let metadata: ScanMetadata
}

/// Scan metadata for upload
struct ScanMetadata: Codable {
    let deviceModel: String
    let iosVersion: String
    let pointCount: Int
    let boundingBox: BoundingBoxMeta
    let captureDate: Date
    let frameCount: Int

    struct BoundingBoxMeta: Codable {
        let minX: Float
        let minY: Float
        let minZ: Float
        let maxX: Float
        let maxY: Float
        let maxZ: Float
    }
}

/// Main service for orchestrating scan processing
@MainActor
@Observable
final class ScanProcessingService {

    // MARK: - Observable Properties

    private(set) var state: ScanProcessingState = .idle
    private(set) var currentScanId: String?
    private(set) var processingStats: ProcessingStats?

    struct ProcessingStats {
        var pointCount: Int = 0
        var fusedFrameCount: Int = 0
        var uploadedBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var elapsedTime: TimeInterval = 0
    }

    // MARK: - Dependencies

    private let apiClient: APIClient
    private let webSocketService: WebSocketService

    // MARK: - Private State

    private var accumulatedPoints: [simd_float3] = []
    private var processingStartTime: Date?

    // MARK: - Configuration

    var configuration = ProcessingConfiguration()

    /// Check if mesh correction ML model is available
    var isMeshCorrectionAvailable: Bool {
        // Check if MeshCorrectionModel.mlmodelc exists in bundle
        return Bundle.main.url(forResource: "MeshCorrectionModel", withExtension: "mlmodelc") != nil
    }

    // MARK: - Initialization

    init(
        apiClient: APIClient = APIClient(),
        webSocketService: WebSocketService = .withDefaultURL()
    ) {
        self.apiClient = apiClient
        self.webSocketService = webSocketService

        setupWebSocketHandlers()
    }

    // MARK: - Public Methods

    /// Start a new scanning session
    func startScanning() {
        state = .scanning(progress: 0)
        processingStartTime = Date()
        processingStats = ProcessingStats()
        accumulatedPoints = []
    }

    /// Process a single AR frame
    func processFrame(_ frame: ARFrame) async throws {
        guard case .scanning(let currentProgress) = state else { return }

        // Update state
        state = .scanning(progress: min(currentProgress + 0.01, 0.99))

        // Extract points from depth data if available
        if let sceneDepth = frame.sceneDepth ?? frame.smoothedSceneDepth {
            let depthMap = sceneDepth.depthMap
            // In production, extract points from depth map
            // For now, just update stats
            processingStats?.fusedFrameCount += 1
        }
    }

    /// Stop scanning and begin local processing
    func stopScanning() async throws -> LocalProcessingResult {
        guard case .scanning = state else {
            throw ProcessingError.invalidState
        }

        state = .processing(stage: .dataPreparation, progress: 0)

        // Create point cloud from accumulated points
        let pointCloud = PointCloud(
            points: accumulatedPoints,
            colors: nil,
            normals: nil,
            confidences: nil
        )

        state = .processing(stage: .dataPreparation, progress: 1.0)

        // Create metadata
        let metadata = ScanMetadata(
            deviceModel: UIDevice.current.model,
            iosVersion: UIDevice.current.systemVersion,
            pointCount: pointCloud.points.count,
            boundingBox: ScanMetadata.BoundingBoxMeta(
                minX: 0, minY: 0, minZ: 0,
                maxX: 0, maxY: 0, maxZ: 0
            ),
            captureDate: processingStartTime ?? Date(),
            frameCount: processingStats?.fusedFrameCount ?? 0
        )

        return LocalProcessingResult(
            pointCloud: pointCloud,
            mesh: nil,
            metadata: metadata
        )
    }

    /// Upload processed data to backend
    func uploadToBackend(_ result: LocalProcessingResult) async throws -> String {
        state = .uploading(progress: 0)

        // Create scan on backend
        let scanResponse = try await apiClient.createScan(name: "Scan \(Date().formatted())")
        let scanId = scanResponse.id
        currentScanId = scanId

        state = .uploading(progress: 0.5)

        // TODO: Implement actual upload
        // For now, simulate progress
        state = .uploading(progress: 1.0)

        return scanId
    }

    /// Start backend AI processing
    func startServerProcessing(scanId: String) async throws {
        state = .serverProcessing(stage: "initializing", progress: 0)

        // Connect WebSocket for real-time updates
        webSocketService.connect()
        try await webSocketService.subscribeTo(scanId: scanId)

        // Start processing
        try await apiClient.startProcessing(scanId: scanId)
    }

    /// Download processed model
    func downloadResult(scanId: String, format: String = "usdz") async throws -> URL {
        state = .downloading(progress: 0)

        let localURL = try await apiClient.downloadModel(scanId: scanId, format: format)

        state = .completed(localURL: localURL)

        return localURL
    }

    /// Cancel current processing
    func cancel() {
        state = .idle
        currentScanId = nil
        webSocketService.disconnect()
    }

    // MARK: - Private Methods

    private func setupWebSocketHandlers() {
        webSocketService.onProcessingUpdate = { [weak self] update in
            Task { @MainActor in
                self?.handleProcessingUpdate(update)
            }
        }

        webSocketService.onError = { [weak self] error in
            Task { @MainActor in
                self?.state = .failed(error: error.message)
            }
        }
    }

    private func handleProcessingUpdate(_ update: WebSocketService.ProcessingUpdate) {
        switch update.status {
        case .processing:
            state = .serverProcessing(stage: update.stage ?? "processing", progress: update.progress)

        case .completed:
            if let scanId = currentScanId {
                Task {
                    try? await downloadResult(scanId: scanId)
                }
            }

        case .failed:
            state = .failed(error: update.message ?? "Processing failed")

        case .queued:
            state = .serverProcessing(stage: "queued", progress: 0)
        }
    }
}

// MARK: - Errors

enum ProcessingError: LocalizedError {
    case invalidState
    case encodingFailed
    case uploadFailed(String)
    case processingFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidState:
            return "Invalid processing state"
        case .encodingFailed:
            return "Failed to encode data"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        }
    }
}
