import Foundation
import ARKit
import Combine

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
    let textureFrames: [CapturedFrame]
    let metadata: ScanMetadata
}

/// Scan metadata for upload
struct ScanMetadata: Codable {
    let deviceModel: String
    let iosVersion: String
    let pointCount: Int
    let boundingBox: BoundingBox
    let captureDate: Date
    let frameCount: Int

    struct BoundingBox: Codable {
        let minX: Float
        let minY: Float
        let minZ: Float
        let maxX: Float
        let maxY: Float
        let maxZ: Float
    }
}

/// Captured camera frame for texture
struct CapturedFrame {
    let image: CVPixelBuffer
    let timestamp: TimeInterval
    let transform: simd_float4x4
    let intrinsics: simd_float3x3
}

/// Main service for orchestrating scan processing
@MainActor
final class ScanProcessingService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var state: ScanProcessingState = .idle
    @Published private(set) var currentScanId: String?
    @Published private(set) var processingStats: ProcessingStats?

    struct ProcessingStats {
        var pointCount: Int = 0
        var fusedFrameCount: Int = 0
        var uploadedBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var elapsedTime: TimeInterval = 0
    }

    // MARK: - Dependencies

    private let depthFusionProcessor: DepthFusionProcessor
    private let pointCloudExtractor: HighResPointCloudExtractor
    private let meshProcessor: MeshAnchorProcessor
    private let apiClient: APIClient
    private let chunkedUploader: ChunkedUploader
    private let webSocketService: WebSocketService

    // MARK: - Private State

    private var accumulatedPointCloud = PointCloud(points: [], colors: [], normals: [])
    private var capturedFrames: [CapturedFrame] = []
    private var processingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Configuration

    var configuration = ProcessingConfiguration()

    // MARK: - Initialization

    init(
        depthFusionProcessor: DepthFusionProcessor = DepthFusionProcessor(),
        pointCloudExtractor: HighResPointCloudExtractor = HighResPointCloudExtractor(),
        meshProcessor: MeshAnchorProcessor = MeshAnchorProcessor(),
        apiClient: APIClient = APIClient(),
        chunkedUploader: ChunkedUploader = ChunkedUploader(),
        webSocketService: WebSocketService = WebSocketService()
    ) {
        self.depthFusionProcessor = depthFusionProcessor
        self.pointCloudExtractor = pointCloudExtractor
        self.meshProcessor = meshProcessor
        self.apiClient = apiClient
        self.chunkedUploader = chunkedUploader
        self.webSocketService = webSocketService

        setupWebSocketHandlers()
    }

    // MARK: - Public Methods

    /// Process a single AR frame with depth fusion
    func processFrame(_ frame: ARFrame) async throws {
        guard state != .idle else { return }

        // Update state to scanning
        if case .scanning(let currentProgress) = state {
            state = .scanning(progress: min(currentProgress + 0.01, 0.99))
        }

        // Fuse depth if enabled
        if configuration.enableDepthFusion {
            let fusionResult = try await depthFusionProcessor.fuseDepth(from: frame)

            // Extract high-res point cloud from fused depth
            let points = try await pointCloudExtractor.extractPointCloud(
                from: fusionResult.fusedDepth,
                confidence: fusionResult.confidenceMap,
                cameraIntrinsics: frame.camera.intrinsics,
                cameraTransform: frame.camera.transform
            )

            // Accumulate points
            accumulatedPointCloud = pointCloudExtractor.mergePointClouds(
                accumulatedPointCloud,
                points
            )

            // Update stats
            processingStats?.fusedFrameCount += 1
            processingStats?.pointCount = accumulatedPointCloud.points.count
        }

        // Capture texture frame periodically (every 30 frames or so)
        if capturedFrames.count < 100, let capturedImage = frame.capturedImage {
            let capturedFrame = CapturedFrame(
                image: capturedImage,
                timestamp: frame.timestamp,
                transform: frame.camera.transform,
                intrinsics: frame.camera.intrinsics
            )
            capturedFrames.append(capturedFrame)
        }
    }

    /// Start a new scanning session
    func startScanning() {
        state = .scanning(progress: 0)
        processingStartTime = Date()
        processingStats = ProcessingStats()
        accumulatedPointCloud = PointCloud(points: [], colors: [], normals: [])
        capturedFrames = []
    }

    /// Stop scanning and begin local processing
    func stopScanning() async throws -> LocalProcessingResult {
        guard case .scanning = state else {
            throw ProcessingError.invalidState
        }

        // Process point cloud
        state = .processing(stage: .pointCloudExtraction, progress: 0)

        // Downsample if needed
        let finalPointCloud: PointCloud
        if accumulatedPointCloud.points.count > configuration.targetPointCount {
            finalPointCloud = pointCloudExtractor.voxelDownsample(
                accumulatedPointCloud,
                voxelSize: calculateVoxelSize(for: configuration.targetPointCount)
            )
        } else {
            finalPointCloud = accumulatedPointCloud
        }

        state = .processing(stage: .pointCloudExtraction, progress: 0.5)

        // Generate mesh if enabled
        var mesh: MeshData? = nil
        if configuration.enableMeshCorrection {
            state = .processing(stage: .meshGeneration, progress: 0)
            // Mesh is generated from ARKit anchors, processed separately
        }

        state = .processing(stage: .dataPreparation, progress: 0)

        // Create metadata
        let boundingBox = calculateBoundingBox(for: finalPointCloud)
        let metadata = ScanMetadata(
            deviceModel: DeviceCapabilities.shared.deviceModel,
            iosVersion: UIDevice.current.systemVersion,
            pointCount: finalPointCloud.points.count,
            boundingBox: boundingBox,
            captureDate: processingStartTime ?? Date(),
            frameCount: capturedFrames.count
        )

        state = .processing(stage: .dataPreparation, progress: 1.0)

        return LocalProcessingResult(
            pointCloud: finalPointCloud,
            mesh: mesh,
            textureFrames: capturedFrames,
            metadata: metadata
        )
    }

    /// Upload processed data to backend
    func uploadToBackend(_ result: LocalProcessingResult) async throws -> String {
        state = .uploading(progress: 0)

        // Create scan on backend
        let scanId = try await apiClient.createScan(
            name: "Scan \(Date().formatted())",
            description: nil
        )
        currentScanId = scanId

        state = .uploading(progress: 0.1)

        // Encode point cloud to PLY
        let plyData = try encodePointCloudToPLY(result.pointCloud)
        processingStats?.totalBytes = Int64(plyData.count)

        // Upload point cloud
        try await chunkedUploader.upload(
            data: plyData,
            to: "/api/v1/scans/\(scanId)/upload",
            filename: "pointcloud.ply",
            progressHandler: { [weak self] progress in
                Task { @MainActor in
                    self?.state = .uploading(progress: 0.1 + progress * 0.7)
                    self?.processingStats?.uploadedBytes = Int64(Float(plyData.count) * progress)
                }
            }
        )

        state = .uploading(progress: 0.8)

        // Upload metadata
        let metadataData = try JSONEncoder().encode(result.metadata)
        try await apiClient.uploadMetadata(scanId: scanId, data: metadataData)

        state = .uploading(progress: 1.0)

        return scanId
    }

    /// Start backend AI processing
    func startServerProcessing(scanId: String) async throws {
        state = .serverProcessing(stage: "initializing", progress: 0)

        // Connect WebSocket for real-time updates
        try await webSocketService.connect(scanId: scanId)

        // Start processing
        try await apiClient.startProcessing(
            scanId: scanId,
            options: ProcessingOptions(
                enableGaussianSplatting: true,
                enableMeshExtraction: true,
                meshResolution: configuration.meshResolution,
                outputFormats: configuration.outputFormats
            )
        )
    }

    /// Download processed model
    func downloadResult(scanId: String, format: String = "usdz") async throws -> URL {
        state = .downloading(progress: 0)

        let localURL = try await apiClient.downloadModel(
            scanId: scanId,
            format: format,
            progressHandler: { [weak self] progress in
                Task { @MainActor in
                    self?.state = .downloading(progress: progress)
                }
            }
        )

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
        webSocketService.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handleWebSocketMessage(message)
            }
        }

        webSocketService.onError = { [weak self] error in
            Task { @MainActor in
                self?.state = .failed(error: error.localizedDescription)
            }
        }
    }

    private func handleWebSocketMessage(_ message: WebSocketMessage) {
        switch message.type {
        case "progress":
            if let data = message.data,
               let stage = data["stage"] as? String,
               let progress = data["progress"] as? Float {
                state = .serverProcessing(stage: stage, progress: progress)
            }

        case "completed":
            if let scanId = currentScanId {
                Task {
                    try? await downloadResult(scanId: scanId)
                }
            }

        case "error":
            if let data = message.data,
               let errorMessage = data["message"] as? String {
                state = .failed(error: errorMessage)
            }

        default:
            break
        }
    }

    private func calculateVoxelSize(for targetCount: Int) -> Float {
        let currentCount = accumulatedPointCloud.points.count
        guard currentCount > 0 else { return 0.01 }

        let ratio = Float(currentCount) / Float(targetCount)
        return 0.005 * pow(ratio, 1.0/3.0)
    }

    private func calculateBoundingBox(for pointCloud: PointCloud) -> ScanMetadata.BoundingBox {
        guard !pointCloud.points.isEmpty else {
            return ScanMetadata.BoundingBox(
                minX: 0, minY: 0, minZ: 0,
                maxX: 0, maxY: 0, maxZ: 0
            )
        }

        var minX: Float = .infinity
        var minY: Float = .infinity
        var minZ: Float = .infinity
        var maxX: Float = -.infinity
        var maxY: Float = -.infinity
        var maxZ: Float = -.infinity

        for point in pointCloud.points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            minZ = min(minZ, point.z)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
            maxZ = max(maxZ, point.z)
        }

        return ScanMetadata.BoundingBox(
            minX: minX, minY: minY, minZ: minZ,
            maxX: maxX, maxY: maxY, maxZ: maxZ
        )
    }

    private func encodePointCloudToPLY(_ pointCloud: PointCloud) throws -> Data {
        var output = ""

        // Header
        output += "ply\n"
        output += "format binary_little_endian 1.0\n"
        output += "element vertex \(pointCloud.points.count)\n"
        output += "property float x\n"
        output += "property float y\n"
        output += "property float z\n"

        if !pointCloud.normals.isEmpty {
            output += "property float nx\n"
            output += "property float ny\n"
            output += "property float nz\n"
        }

        if !pointCloud.colors.isEmpty {
            output += "property uchar red\n"
            output += "property uchar green\n"
            output += "property uchar blue\n"
        }

        output += "end_header\n"

        // Convert header to data
        var data = output.data(using: .ascii) ?? Data()

        // Write binary vertex data
        for i in 0..<pointCloud.points.count {
            let point = pointCloud.points[i]

            // Position
            var x = point.x
            var y = point.y
            var z = point.z
            data.append(Data(bytes: &x, count: 4))
            data.append(Data(bytes: &y, count: 4))
            data.append(Data(bytes: &z, count: 4))

            // Normals
            if !pointCloud.normals.isEmpty {
                let normal = pointCloud.normals[i]
                var nx = normal.x
                var ny = normal.y
                var nz = normal.z
                data.append(Data(bytes: &nx, count: 4))
                data.append(Data(bytes: &ny, count: 4))
                data.append(Data(bytes: &nz, count: 4))
            }

            // Colors
            if !pointCloud.colors.isEmpty {
                let color = pointCloud.colors[i]
                var r = UInt8(min(255, max(0, color.x * 255)))
                var g = UInt8(min(255, max(0, color.y * 255)))
                var b = UInt8(min(255, max(0, color.z * 255)))
                data.append(Data(bytes: &r, count: 1))
                data.append(Data(bytes: &g, count: 1))
                data.append(Data(bytes: &b, count: 1))
            }
        }

        return data
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

// MARK: - API Extensions

extension APIClient {
    func createScan(name: String, description: String?) async throws -> String {
        struct CreateScanRequest: Encodable {
            let name: String
            let description: String?
        }

        struct CreateScanResponse: Decodable {
            let id: String
        }

        let request = CreateScanRequest(name: name, description: description)
        let response: CreateScanResponse = try await post("/api/v1/scans", body: request)
        return response.id
    }

    func uploadMetadata(scanId: String, data: Data) async throws {
        try await uploadData(
            data,
            to: "/api/v1/scans/\(scanId)/metadata",
            contentType: "application/json"
        )
    }

    func startProcessing(scanId: String, options: ProcessingOptions) async throws {
        try await post("/api/v1/scans/\(scanId)/process", body: options)
    }

    func downloadModel(
        scanId: String,
        format: String,
        progressHandler: @escaping (Float) -> Void
    ) async throws -> URL {
        let url = "/api/v1/scans/\(scanId)/download?format=\(format)"
        return try await downloadFile(from: url, progressHandler: progressHandler)
    }
}

struct ProcessingOptions: Encodable {
    let enableGaussianSplatting: Bool
    let enableMeshExtraction: Bool
    let meshResolution: String
    let outputFormats: [String]

    enum CodingKeys: String, CodingKey {
        case enableGaussianSplatting = "enable_gaussian_splatting"
        case enableMeshExtraction = "enable_mesh_extraction"
        case meshResolution = "mesh_resolution"
        case outputFormats = "output_formats"
    }
}
