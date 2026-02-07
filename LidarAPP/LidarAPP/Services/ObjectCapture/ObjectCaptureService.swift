import Foundation
import RealityKit
import ARKit
import Combine
import simd

// MARK: - Object Capture Service Protocol

protocol ObjectCaptureServiceProtocol {
    var captureStatus: AnyPublisher<ObjectCaptureStatus, Never> { get }
    var captureProgress: AnyPublisher<Float, Never> { get }
    var imageCount: AnyPublisher<Int, Never> { get }

    func startCapture() async throws
    func stopCapture() async -> ObjectCaptureResult?
    func cancelCapture()
}

// MARK: - Object Capture Status

enum ObjectCaptureStatus: Equatable {
    case idle
    case preparing
    case capturing
    case processing
    case completed(URL?)
    case failed(String)

    var displayName: String {
        switch self {
        case .idle: return "Připraveno"
        case .preparing: return "Příprava..."
        case .capturing: return "Skenování"
        case .processing: return "Zpracování..."
        case .completed: return "Dokončeno"
        case .failed: return "Chyba"
        }
    }

    static func == (lhs: ObjectCaptureStatus, rhs: ObjectCaptureStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.preparing, .preparing), (.capturing, .capturing), (.processing, .processing):
            return true
        case (.completed(let a), .completed(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Object Capture Result

struct ObjectCaptureResult {
    let modelURL: URL?
    let pointCloud: PointCloud?
    let meshData: MeshData?
    let imageCount: Int
    let boundingBox: (min: simd_float3, max: simd_float3)?
}

// MARK: - Object Capture Service

/// Service for capturing 3D objects on iOS.
/// Uses LiDAR + camera capture, then processes on backend with Gaussian Splatting.
/// Note: Apple's ObjectCaptureSession is macOS-only; this is our iOS implementation.
@MainActor
final class ObjectCaptureService: NSObject, ObjectCaptureServiceProtocol {

    static let shared = ObjectCaptureService()

    // MARK: - Properties

    private var capturedImages: [URL] = []
    private var outputURL: URL?

    private let statusSubject = CurrentValueSubject<ObjectCaptureStatus, Never>(.idle)
    private let progressSubject = PassthroughSubject<Float, Never>()
    private let imageCountSubject = CurrentValueSubject<Int, Never>(0)

    var captureStatus: AnyPublisher<ObjectCaptureStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    var captureProgress: AnyPublisher<Float, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    var imageCount: AnyPublisher<Int, Never> {
        imageCountSubject.eraseToAnyPublisher()
    }

    /// Object capture is supported on devices with LiDAR
    static var isSupported: Bool {
        return DeviceCapabilities.hasLiDAR
    }

    var currentStatus: ObjectCaptureStatus {
        statusSubject.value
    }

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Capture Control

    /// Accumulated mesh data from real AR capture
    private var capturedMeshData: [MeshData] = []

    func startCapture() async throws {
        guard Self.isSupported || MockDataProvider.isMockModeEnabled else {
            throw ObjectCaptureError.notSupported
        }

        // Request camera permission before starting
        let cameraGranted = await DeviceCapabilities.requestCameraPermission()
        guard cameraGranted else {
            statusSubject.send(.failed("Přístup ke kameře zamítnut"))
            throw ObjectCaptureError.captureFailed
        }

        statusSubject.send(.preparing)
        capturedImages = []
        capturedMeshData = []
        imageCountSubject.send(0)

        // Create output directory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let captureDir = documentsDir.appendingPathComponent("ObjectCapture/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)

        outputURL = captureDir

        statusSubject.send(.capturing)
    }

    func stopCapture() async -> ObjectCaptureResult? {
        statusSubject.send(.processing)

        // Wait for any pending operations
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Build point cloud and unified mesh from captured mesh data
        var pointCloud: PointCloud? = nil
        var unifiedMesh: MeshData? = nil
        var boundingBox: (min: simd_float3, max: simd_float3)? = nil

        if !capturedMeshData.isEmpty {
            // Build point cloud from mesh vertices
            var allPoints: [simd_float3] = []
            var allNormals: [simd_float3] = []

            for mesh in capturedMeshData {
                allPoints.append(contentsOf: mesh.worldVertices)
                allNormals.append(contentsOf: mesh.normals)
            }

            if !allPoints.isEmpty {
                pointCloud = PointCloud(
                    points: allPoints,
                    normals: allNormals,
                    metadata: PointCloudMetadata(source: .lidar)
                )

                // Compute bounding box
                var minPt = allPoints[0]
                var maxPt = allPoints[0]
                for pt in allPoints {
                    minPt = simd_min(minPt, pt)
                    maxPt = simd_max(maxPt, pt)
                }
                boundingBox = (min: minPt, max: maxPt)
            }

            // Build unified mesh
            let combined = CombinedMesh()
            for mesh in capturedMeshData {
                combined.addOrUpdate(mesh)
            }
            unifiedMesh = combined.toUnifiedMesh()
        }

        // Create result
        let result = ObjectCaptureResult(
            modelURL: outputURL,
            pointCloud: pointCloud,
            meshData: unifiedMesh,
            imageCount: imageCountSubject.value,
            boundingBox: boundingBox
        )

        statusSubject.send(.completed(outputURL))

        return result
    }

    func cancelCapture() {
        statusSubject.send(.idle)
        imageCountSubject.send(0)
        capturedMeshData = []
    }

    /// Add a captured image to the session
    func addCapturedImage(at url: URL) {
        capturedImages.append(url)
        imageCountSubject.send(capturedImages.count)

        // Update progress (assuming ~50 images for good capture)
        let progress = min(Float(capturedImages.count) / 50.0, 0.95)
        progressSubject.send(progress)
    }

    /// Add captured mesh data from AR session (called by Coordinator)
    func updateCapturedMeshData(_ meshes: [MeshData]) {
        capturedMeshData = meshes
    }

    // MARK: - Conversion

    func convertToScanSession() -> ScanSession {
        return convertToScanSession(withMeshes: nil, trajectory: nil, imageCount: nil)
    }

    /// Convert captured data into a ScanSession, optionally using externally provided mesh data
    func convertToScanSession(
        withMeshes meshes: [MeshData]?,
        trajectory: [simd_float4x4]?,
        imageCount: Int?
    ) -> ScanSession {
        let session = ScanSession(name: "Object Scan")

        // For mock mode, generate sample point cloud
        if MockDataProvider.isMockModeEnabled {
            session.pointCloud = MockDataProvider.shared.generateObjectPointCloud()
            return session
        }

        // Use provided meshes or fall back to internally captured ones
        let activeMeshes = meshes ?? capturedMeshData

        // Real device: populate session from captured mesh data
        if !activeMeshes.isEmpty {
            // Add meshes to session
            for mesh in activeMeshes {
                session.addMesh(mesh)
            }

            // Build point cloud from mesh vertices
            var allPoints: [simd_float3] = []
            var allNormals: [simd_float3] = []

            for mesh in activeMeshes {
                allPoints.append(contentsOf: mesh.worldVertices)
                allNormals.append(contentsOf: mesh.normals)
            }

            // Subsample if too many points
            let maxPoints = DeviceCapabilities.recommendedMaxPoints
            if allPoints.count > maxPoints {
                let stride = allPoints.count / maxPoints
                var sampledPoints: [simd_float3] = []
                var sampledNormals: [simd_float3] = []
                for i in Swift.stride(from: 0, to: allPoints.count, by: stride) {
                    sampledPoints.append(allPoints[i])
                    sampledNormals.append(allNormals[i])
                }
                allPoints = sampledPoints
                allNormals = sampledNormals
            }

            if !allPoints.isEmpty {
                session.pointCloud = PointCloud(
                    points: allPoints,
                    normals: allNormals,
                    metadata: PointCloudMetadata(source: .lidar)
                )
            }
        }

        // Add camera trajectory if available
        if let trajectory = trajectory {
            for transform in trajectory {
                session.addCameraPosition(transform)
            }
        }

        return session
    }
}

// MARK: - Errors

enum ObjectCaptureError: LocalizedError {
    case notSupported
    case sessionCreationFailed
    case captureFailed
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Object Capture vyžaduje zařízení s LiDAR senzorem."
        case .sessionCreationFailed:
            return "Nepodařilo se vytvořit capture session"
        case .captureFailed:
            return "Skenování objektu selhalo"
        case .processingFailed(let message):
            return "Zpracování selhalo: \(message)"
        }
    }
}
