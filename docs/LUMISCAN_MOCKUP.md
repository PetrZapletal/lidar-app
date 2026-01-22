# LUMISCAN - iOS 3D LiDAR Scanner App
## Technical MockUp Specification for Development

---

## PROJECT OVERVIEW

**App Name:** Lumiscan
**Platform:** iOS 15.0+
**Devices:** iPhone 12 Pro+, iPhone 13 Pro+, iPhone 14 Pro+, iPhone 15 Pro+, iPhone 16 Pro+, iPad Pro (2020+)
**Language:** Swift 5.9
**UI Framework:** SwiftUI
**Architecture:** MVVM + Clean Architecture
**Minimum LiDAR:** Required for full functionality (fallback photogrammetry for non-LiDAR)

---

## TECH STACK

### iOS Frameworks
```
- SwiftUI (UI)
- ARKit 6 (AR/LiDAR)
- RealityKit (3D Rendering)
- RoomPlan (Interior scanning)
- Metal (GPU acceleration)
- Core ML (On-device AI)
- AVFoundation (Camera)
- CoreLocation (GPS)
- CloudKit (Sync)
- StoreKit 2 (Subscriptions)
```

### Third-Party Dependencies
```swift
// Package.swift dependencies
dependencies: [
    .package(url: "https://github.com/Alamofire/Alamofire", from: "5.8.0"),
    .package(url: "https://github.com/realm/realm-swift", from: "10.45.0"),
    .package(url: "https://github.com/airbnb/lottie-ios", from: "4.3.0"),
    .package(url: "https://github.com/kean/Nuke", from: "12.0.0"),
    .package(url: "https://github.com/RevenueCat/purchases-ios", from: "4.31.0"),
]
```

### Cloud Backend
```
- AWS Lambda (Serverless functions)
- AWS API Gateway (REST API)
- AWS S3 (File storage)
- AWS EC2 P4d (GPU processing - NVIDIA A100)
- AWS CloudFront (CDN)
- AWS RDS PostgreSQL (Database)
- AWS ElastiCache Redis (Queue/Cache)
- AWS Cognito (Authentication)
```

### AI/ML Processing
```
- PyTorch (NeRF, Gaussian Splatting)
- COLMAP (Structure from Motion)
- Open3D (Point cloud processing)
- Core ML (On-device inference)
```

---

## APP STRUCTURE

```
Lumiscan/
├── App/
│   ├── LumiscanApp.swift
│   ├── AppDelegate.swift
│   └── SceneDelegate.swift
├── Core/
│   ├── DI/
│   │   └── DependencyContainer.swift
│   ├── Extensions/
│   ├── Utilities/
│   └── Constants.swift
├── Data/
│   ├── Repositories/
│   │   ├── ScanRepository.swift
│   │   ├── UserRepository.swift
│   │   └── CloudRepository.swift
│   ├── DataSources/
│   │   ├── Local/
│   │   │   ├── RealmDataSource.swift
│   │   │   └── FileManagerDataSource.swift
│   │   └── Remote/
│   │       ├── APIClient.swift
│   │       └── CloudProcessingAPI.swift
│   └── Models/
│       ├── Scan.swift
│       ├── ScanMode.swift
│       ├── ExportFormat.swift
│       └── ProcessingJob.swift
├── Domain/
│   ├── UseCases/
│   │   ├── Scanning/
│   │   │   ├── StartScanUseCase.swift
│   │   │   ├── StopScanUseCase.swift
│   │   │   └── ProcessScanUseCase.swift
│   │   ├── Export/
│   │   │   ├── ExportMeshUseCase.swift
│   │   │   └── ExportPointCloudUseCase.swift
│   │   └── Measurement/
│   │       └── MeasureDistanceUseCase.swift
│   └── Entities/
│       ├── ScanEntity.swift
│       └── MeasurementEntity.swift
├── Presentation/
│   ├── Screens/
│   │   ├── Home/
│   │   │   ├── HomeView.swift
│   │   │   └── HomeViewModel.swift
│   │   ├── Scan/
│   │   │   ├── ScanView.swift
│   │   │   ├── ScanViewModel.swift
│   │   │   └── Components/
│   │   │       ├── ScanModeSelector.swift
│   │   │       ├── ScanProgressOverlay.swift
│   │   │       └── QualityIndicator.swift
│   │   ├── Preview/
│   │   │   ├── ModelPreviewView.swift
│   │   │   ├── ModelPreviewViewModel.swift
│   │   │   └── Components/
│   │   │       ├── ARQuickLookView.swift
│   │   │       └── MeasurementToolbar.swift
│   │   ├── Export/
│   │   │   ├── ExportView.swift
│   │   │   └── ExportViewModel.swift
│   │   ├── Library/
│   │   │   ├── LibraryView.swift
│   │   │   └── LibraryViewModel.swift
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   └── SubscriptionView.swift
│   │   └── Onboarding/
│   │       └── OnboardingView.swift
│   ├── Components/
│   │   ├── PrimaryButton.swift
│   │   ├── ScanCard.swift
│   │   ├── LoadingOverlay.swift
│   │   └── ProgressRing.swift
│   └── Theme/
│       ├── Colors.swift
│       ├── Fonts.swift
│       └── Spacing.swift
├── Services/
│   ├── LiDAR/
│   │   ├── LiDARService.swift
│   │   ├── LiDARSessionManager.swift
│   │   └── PointCloudProcessor.swift
│   ├── RoomPlan/
│   │   ├── RoomPlanService.swift
│   │   └── RoomPlanDelegate.swift
│   ├── Processing/
│   │   ├── GaussianSplattingProcessor.swift
│   │   ├── MeshOptimizer.swift
│   │   └── TextureMapper.swift
│   ├── Export/
│   │   ├── OBJExporter.swift
│   │   ├── USDZExporter.swift
│   │   ├── GLTFExporter.swift
│   │   ├── STLExporter.swift
│   │   ├── PointCloudExporter.swift
│   │   └── FloorPlanExporter.swift
│   ├── Cloud/
│   │   ├── CloudProcessingService.swift
│   │   ├── UploadManager.swift
│   │   └── JobStatusTracker.swift
│   ├── Measurement/
│   │   ├── MeasurementService.swift
│   │   └── ARMeasurementOverlay.swift
│   └── Subscription/
│       ├── SubscriptionService.swift
│       └── RevenueCatManager.swift
└── Resources/
    ├── Assets.xcassets
    ├── Localizable.strings
    ├── ML Models/
    │   └── HoleFilling.mlmodel
    └── Info.plist
```

---

## DATA MODELS

### Scan Model
```swift
import Foundation
import RealmSwift

enum ScanMode: String, Codable, PersistableEnum {
    case exterior
    case interior
    case object
}

enum ScanStatus: String, Codable, PersistableEnum {
    case capturing
    case processing
    case completed
    case failed
    case cloudProcessing
}

enum ProcessingQuality: String, Codable, PersistableEnum {
    case preview    // Real-time, low quality
    case standard   // On-device processing
    case high       // Cloud processing
    case ultra      // Cloud + AI enhancement
}

class Scan: Object, Identifiable {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var name: String = ""
    @Persisted var mode: ScanMode = .object
    @Persisted var status: ScanStatus = .capturing
    @Persisted var quality: ProcessingQuality = .standard
    @Persisted var createdAt: Date = Date()
    @Persisted var updatedAt: Date = Date()
    
    // Metadata
    @Persisted var pointCount: Int = 0
    @Persisted var faceCount: Int = 0
    @Persisted var fileSize: Int64 = 0
    @Persisted var duration: TimeInterval = 0
    
    // Location
    @Persisted var latitude: Double?
    @Persisted var longitude: Double?
    @Persisted var address: String?
    
    // Dimensions (in meters)
    @Persisted var width: Double?
    @Persisted var height: Double?
    @Persisted var depth: Double?
    
    // Files
    @Persisted var thumbnailPath: String?
    @Persisted var meshPath: String?
    @Persisted var pointCloudPath: String?
    @Persisted var texturePath: String?
    @Persisted var rawDataPath: String?
    
    // Cloud
    @Persisted var cloudJobId: String?
    @Persisted var cloudProgress: Double = 0
    @Persisted var isUploaded: Bool = false
    
    // Room Plan specific (Interior mode)
    @Persisted var roomCount: Int = 0
    @Persisted var totalArea: Double = 0  // m²
    @Persisted var floorPlanPath: String?
}
```

### Measurement Model
```swift
struct Measurement: Identifiable, Codable {
    let id: UUID
    let scanId: String
    let type: MeasurementType
    let points: [SIMD3<Float>]
    let value: Double  // meters
    let unit: MeasurementUnit
    let createdAt: Date
    
    enum MeasurementType: String, Codable {
        case distance
        case area
        case volume
        case angle
    }
    
    enum MeasurementUnit: String, Codable {
        case meters
        case centimeters
        case feet
        case inches
    }
}
```

### Export Format Model
```swift
enum ExportFormat: String, CaseIterable, Identifiable {
    // 3D Mesh
    case obj
    case fbx
    case gltf
    case glb
    case usdz
    case stl
    case dae
    
    // Point Cloud
    case ply
    case pts
    case pcd
    case xyz
    case las
    case e57
    
    // CAD
    case dxf
    case dwg
    case rvt
    case ifc
    
    // 2D
    case pdf
    case png
    case svg
    
    // Video/AR
    case mp4
    case mov
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .obj: return "OBJ (Wavefront)"
        case .fbx: return "FBX (Autodesk)"
        case .gltf: return "glTF"
        case .glb: return "GLB (Binary glTF)"
        case .usdz: return "USDZ (Apple AR)"
        case .stl: return "STL (3D Print)"
        case .dae: return "DAE (Collada)"
        case .ply: return "PLY (Point Cloud)"
        case .pts: return "PTS (Point Cloud)"
        case .pcd: return "PCD (PCL Format)"
        case .xyz: return "XYZ (ASCII)"
        case .las: return "LAS (LiDAR)"
        case .e57: return "E57 (ASTM Standard)"
        case .dxf: return "DXF (AutoCAD)"
        case .dwg: return "DWG (AutoCAD)"
        case .rvt: return "RVT (Revit)"
        case .ifc: return "IFC (BIM)"
        case .pdf: return "PDF (Floor Plan)"
        case .png: return "PNG (Image)"
        case .svg: return "SVG (Vector)"
        case .mp4: return "MP4 (Video)"
        case .mov: return "MOV (Video)"
        }
    }
    
    var category: ExportCategory {
        switch self {
        case .obj, .fbx, .gltf, .glb, .usdz, .stl, .dae:
            return .mesh
        case .ply, .pts, .pcd, .xyz, .las, .e57:
            return .pointCloud
        case .dxf, .dwg, .rvt, .ifc:
            return .cad
        case .pdf, .png, .svg:
            return .twoDimensional
        case .mp4, .mov:
            return .video
        }
    }
    
    var requiresPro: Bool {
        switch self {
        case .obj, .usdz, .glb, .ply, .png:
            return false
        default:
            return true
        }
    }
    
    var requiresBusiness: Bool {
        switch self {
        case .dxf, .dwg, .rvt, .ifc, .e57:
            return true
        default:
            return false
        }
    }
}

enum ExportCategory: String {
    case mesh = "3D Mesh"
    case pointCloud = "Point Cloud"
    case cad = "CAD"
    case twoDimensional = "2D Plans"
    case video = "Video/AR"
}
```

### Subscription Model
```swift
enum SubscriptionTier: String, Codable {
    case free
    case pro
    case business
    case enterprise
    
    var monthlyPrice: Decimal {
        switch self {
        case .free: return 0
        case .pro: return 9.99
        case .business: return 29.99
        case .enterprise: return 0  // Custom pricing
        }
    }
    
    var scansPerMonth: Int? {
        switch self {
        case .free: return 5
        case .pro, .business, .enterprise: return nil  // Unlimited
        }
    }
    
    var cloudProcessingMinutes: Int {
        switch self {
        case .free: return 30
        case .pro: return 300
        case .business: return 1000
        case .enterprise: return Int.max
        }
    }
    
    var maxScanArea: Double? {  // m²
        switch self {
        case .free: return 50
        case .pro: return 500
        case .business, .enterprise: return nil
        }
    }
    
    var features: [Feature] {
        switch self {
        case .free:
            return [.basicScanning, .basicExport, .measurement, .arPreview]
        case .pro:
            return Feature.allCases.filter { !$0.requiresBusiness }
        case .business, .enterprise:
            return Feature.allCases
        }
    }
    
    enum Feature: String, CaseIterable {
        case basicScanning
        case basicExport
        case measurement
        case arPreview
        case unlimitedScans
        case allExportFormats
        case cloudProcessing
        case hdProcessing
        case nerf
        case nsr
        case aiHoleFilling
        case multiRoomStitching
        case cadExport
        case api
        case teamFeatures
        case prioritySupport
        
        var requiresBusiness: Bool {
            switch self {
            case .cadExport, .api, .teamFeatures, .prioritySupport:
                return true
            default:
                return false
            }
        }
    }
}
```

---

## CORE SERVICES

### LiDAR Service
```swift
import ARKit
import RealityKit
import Combine

protocol LiDARServiceProtocol {
    var isSupported: Bool { get }
    var isRunning: Bool { get }
    var currentPointCloud: AnyPublisher<PointCloud, Never> { get }
    var currentMesh: AnyPublisher<MeshResource, Never> { get }
    var scanProgress: AnyPublisher<ScanProgress, Never> { get }
    
    func startSession(mode: ScanMode, quality: ProcessingQuality) async throws
    func stopSession() async
    func pauseSession()
    func resumeSession()
    func captureSnapshot() async throws -> ScanSnapshot
}

struct ScanProgress {
    let pointCount: Int
    let coverage: Float  // 0.0 - 1.0
    let quality: Float   // 0.0 - 1.0
    let trackingState: ARCamera.TrackingState
    let duration: TimeInterval
}

struct PointCloud {
    let points: [SIMD3<Float>]
    let colors: [SIMD4<Float>]?
    let normals: [SIMD3<Float>]?
    let confidences: [Float]?
}

struct ScanSnapshot {
    let pointCloud: PointCloud
    let mesh: MeshResource?
    let texture: UIImage?
    let timestamp: Date
    let cameraTransform: simd_float4x4
}

final class LiDARService: NSObject, LiDARServiceProtocol {
    
    static let shared = LiDARService()
    
    private var arSession: ARSession?
    private var arView: ARView?
    
    private let pointCloudSubject = PassthroughSubject<PointCloud, Never>()
    private let meshSubject = PassthroughSubject<MeshResource, Never>()
    private let progressSubject = PassthroughSubject<ScanProgress, Never>()
    
    var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    
    var isRunning: Bool {
        arSession?.currentFrame != nil
    }
    
    var currentPointCloud: AnyPublisher<PointCloud, Never> {
        pointCloudSubject.eraseToAnyPublisher()
    }
    
    var currentMesh: AnyPublisher<MeshResource, Never> {
        meshSubject.eraseToAnyPublisher()
    }
    
    var scanProgress: AnyPublisher<ScanProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    func startSession(mode: ScanMode, quality: ProcessingQuality) async throws {
        guard isSupported else {
            throw LiDARError.notSupported
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        configuration.environmentTexturing = .automatic
        
        if mode == .exterior {
            configuration.worldAlignment = .gravityAndHeading
        }
        
        arSession = ARSession()
        arSession?.delegate = self
        arSession?.run(configuration)
    }
    
    func stopSession() async {
        arSession?.pause()
        arSession = nil
    }
    
    func pauseSession() {
        arSession?.pause()
    }
    
    func resumeSession() {
        guard let configuration = arSession?.configuration else { return }
        arSession?.run(configuration)
    }
    
    func captureSnapshot() async throws -> ScanSnapshot {
        guard let frame = arSession?.currentFrame else {
            throw LiDARError.noFrame
        }
        
        // Extract point cloud from depth data
        let pointCloud = try extractPointCloud(from: frame)
        
        // Generate mesh if available
        let mesh = try? await generateMesh(from: frame)
        
        // Capture texture
        let texture = UIImage(pixelBuffer: frame.capturedImage)
        
        return ScanSnapshot(
            pointCloud: pointCloud,
            mesh: mesh,
            texture: texture,
            timestamp: Date(),
            cameraTransform: frame.camera.transform
        )
    }
    
    private func extractPointCloud(from frame: ARFrame) throws -> PointCloud {
        guard let depthMap = frame.sceneDepth?.depthMap else {
            throw LiDARError.noDepthData
        }
        
        // Convert depth map to point cloud
        var points: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        
        // ... depth map processing implementation
        
        return PointCloud(points: points, colors: colors, normals: nil, confidences: nil)
    }
    
    private func generateMesh(from frame: ARFrame) async throws -> MeshResource {
        // ... mesh generation implementation
        fatalError("Implementation required")
    }
}

extension LiDARService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Process frame and emit updates
        Task {
            if let pointCloud = try? extractPointCloud(from: frame) {
                pointCloudSubject.send(pointCloud)
            }
            
            let progress = ScanProgress(
                pointCount: 0,  // Calculate from accumulated data
                coverage: 0,
                quality: 0,
                trackingState: frame.camera.trackingState,
                duration: 0
            )
            progressSubject.send(progress)
        }
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                // Process mesh anchor
                processMeshAnchor(meshAnchor)
            }
        }
    }
    
    private func processMeshAnchor(_ anchor: ARMeshAnchor) {
        // Convert ARMeshGeometry to MeshResource
        // ... implementation
    }
}

enum LiDARError: Error {
    case notSupported
    case noFrame
    case noDepthData
    case processingFailed
}
```

### RoomPlan Service (Interior Mode)
```swift
import RoomPlan
import Combine

protocol RoomPlanServiceProtocol {
    var isSupported: Bool { get }
    var capturedRooms: AnyPublisher<[CapturedRoom], Never> { get }
    var scanProgress: AnyPublisher<Float, Never> { get }
    
    func startCapture() async throws
    func stopCapture() async -> CapturedStructure?
    func exportFloorPlan(structure: CapturedStructure) async throws -> URL
}

final class RoomPlanService: NSObject, RoomPlanServiceProtocol {
    
    static let shared = RoomPlanService()
    
    private var roomCaptureSession: RoomCaptureSession?
    private var capturedStructure: CapturedStructure?
    
    private let roomsSubject = PassthroughSubject<[CapturedRoom], Never>()
    private let progressSubject = PassthroughSubject<Float, Never>()
    
    var isSupported: Bool {
        RoomCaptureSession.isSupported
    }
    
    var capturedRooms: AnyPublisher<[CapturedRoom], Never> {
        roomsSubject.eraseToAnyPublisher()
    }
    
    var scanProgress: AnyPublisher<Float, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    func startCapture() async throws {
        guard isSupported else {
            throw RoomPlanError.notSupported
        }
        
        roomCaptureSession = RoomCaptureSession()
        roomCaptureSession?.delegate = self
        
        let config = RoomCaptureSession.Configuration()
        roomCaptureSession?.run(configuration: config)
    }
    
    func stopCapture() async -> CapturedStructure? {
        roomCaptureSession?.stop()
        return capturedStructure
    }
    
    func exportFloorPlan(structure: CapturedStructure) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("floorplan_\(UUID().uuidString).usdz")
        
        try structure.export(to: tempURL)
        return tempURL
    }
}

extension RoomPlanService: RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        roomsSubject.send([room])
    }
    
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        if let error = error {
            print("RoomPlan error: \(error)")
            return
        }
        
        // Process final structure
        Task {
            do {
                let structureBuilder = StructureBuilder(options: [.beautifyObjects])
                capturedStructure = try await structureBuilder.capturedStructure(from: data)
            } catch {
                print("Structure building failed: \(error)")
            }
        }
    }
}

enum RoomPlanError: Error {
    case notSupported
    case captureFailed
    case exportFailed
}
```

### Gaussian Splatting Processor
```swift
import Metal
import MetalKit
import CoreML

protocol GaussianSplattingProcessorProtocol {
    func process(pointCloud: PointCloud, progress: @escaping (Float) -> Void) async throws -> GaussianSplatModel
    func render(model: GaussianSplatModel, viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4) -> MTLTexture?
}

struct GaussianSplatModel {
    let positions: [SIMD3<Float>]
    let covariances: [simd_float3x3]
    let colors: [SIMD4<Float>]
    let opacities: [Float]
    let sphericalHarmonics: [[Float]]?
}

final class GaussianSplattingProcessor: GaussianSplattingProcessorProtocol {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ProcessingError.metalNotAvailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw ProcessingError.metalNotAvailable
        }
        guard let library = device.makeDefaultLibrary() else {
            throw ProcessingError.metalNotAvailable
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.library = library
    }
    
    func process(pointCloud: PointCloud, progress: @escaping (Float) -> Void) async throws -> GaussianSplatModel {
        // 1. Initialize Gaussians from point cloud
        progress(0.1)
        var gaussians = initializeGaussians(from: pointCloud)
        
        // 2. Optimize Gaussians (simplified on-device version)
        progress(0.3)
        gaussians = try await optimizeGaussians(gaussians, iterations: 1000) { optimProgress in
            progress(0.3 + optimProgress * 0.6)
        }
        
        // 3. Prune low-opacity Gaussians
        progress(0.9)
        gaussians = pruneGaussians(gaussians)
        
        progress(1.0)
        return gaussians
    }
    
    func render(model: GaussianSplatModel, viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4) -> MTLTexture? {
        // Render Gaussians using Metal
        // ... implementation
        return nil
    }
    
    private func initializeGaussians(from pointCloud: PointCloud) -> GaussianSplatModel {
        // Initialize each point as a small Gaussian
        let positions = pointCloud.points
        let covariances = positions.map { _ in
            simd_float3x3(diagonal: SIMD3<Float>(0.0001, 0.0001, 0.0001))
        }
        let colors = pointCloud.colors ?? positions.map { _ in SIMD4<Float>(0.5, 0.5, 0.5, 1.0) }
        let opacities = positions.map { _ in Float(1.0) }
        
        return GaussianSplatModel(
            positions: positions,
            covariances: covariances,
            colors: colors,
            opacities: opacities,
            sphericalHarmonics: nil
        )
    }
    
    private func optimizeGaussians(_ model: GaussianSplatModel, iterations: Int, progress: @escaping (Float) -> Void) async throws -> GaussianSplatModel {
        // Simplified optimization for on-device processing
        // Full optimization happens in cloud
        // ... implementation
        return model
    }
    
    private func pruneGaussians(_ model: GaussianSplatModel) -> GaussianSplatModel {
        // Remove Gaussians with very low opacity
        // ... implementation
        return model
    }
}

enum ProcessingError: Error {
    case metalNotAvailable
    case processingFailed
    case insufficientMemory
}
```

### Cloud Processing Service
```swift
import Foundation
import Combine

protocol CloudProcessingServiceProtocol {
    func uploadScan(_ scan: Scan, data: Data, progress: @escaping (Float) -> Void) async throws -> String
    func startProcessing(jobId: String, options: ProcessingOptions) async throws
    func getJobStatus(jobId: String) async throws -> ProcessingJobStatus
    func downloadResult(jobId: String, progress: @escaping (Float) -> Void) async throws -> URL
    func cancelJob(jobId: String) async throws
}

struct ProcessingOptions: Codable {
    let quality: ProcessingQuality
    let technologies: [ProcessingTechnology]
    let outputFormats: [ExportFormat]
    let enableHoleFilling: Bool
    let enableTextureEnhancement: Bool
    
    enum ProcessingTechnology: String, Codable {
        case gaussianSplatting
        case nerf
        case nsr
        case photogrammetry
    }
}

struct ProcessingJobStatus: Codable {
    let jobId: String
    let status: Status
    let progress: Float
    let estimatedTimeRemaining: TimeInterval?
    let error: String?
    let resultUrls: [String: URL]?
    
    enum Status: String, Codable {
        case queued
        case processing
        case completed
        case failed
        case cancelled
    }
}

final class CloudProcessingService: CloudProcessingServiceProtocol {
    
    private let apiClient: APIClient
    private let uploadManager: UploadManager
    
    init(apiClient: APIClient, uploadManager: UploadManager) {
        self.apiClient = apiClient
        self.uploadManager = uploadManager
    }
    
    func uploadScan(_ scan: Scan, data: Data, progress: @escaping (Float) -> Void) async throws -> String {
        // 1. Get presigned URL
        let presignedURL = try await apiClient.getPresignedUploadURL(scanId: scan.id)
        
        // 2. Upload data with progress
        try await uploadManager.upload(
            data: data,
            to: presignedURL,
            progress: progress
        )
        
        // 3. Confirm upload
        let jobId = try await apiClient.confirmUpload(scanId: scan.id)
        
        return jobId
    }
    
    func startProcessing(jobId: String, options: ProcessingOptions) async throws {
        try await apiClient.startProcessing(jobId: jobId, options: options)
    }
    
    func getJobStatus(jobId: String) async throws -> ProcessingJobStatus {
        try await apiClient.getJobStatus(jobId: jobId)
    }
    
    func downloadResult(jobId: String, progress: @escaping (Float) -> Void) async throws -> URL {
        // 1. Get download URLs
        let status = try await getJobStatus(jobId: jobId)
        guard let resultUrls = status.resultUrls,
              let meshUrl = resultUrls["mesh"] else {
            throw CloudError.noResults
        }
        
        // 2. Download file
        let localURL = try await uploadManager.download(
            from: meshUrl,
            progress: progress
        )
        
        return localURL
    }
    
    func cancelJob(jobId: String) async throws {
        try await apiClient.cancelJob(jobId: jobId)
    }
}

enum CloudError: Error {
    case uploadFailed
    case processingFailed
    case noResults
    case downloadFailed
}
```

---

## UI SCREENS

### Home Screen
```swift
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var showNewScan = false
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Quick Actions
                quickActionsView
                
                // Recent Scans
                recentScansView
                
                Spacer()
            }
            .navigationTitle("Lumiscan")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showNewScan = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .fullScreenCover(isPresented: $showNewScan) {
                ScanModeSelectionView()
            }
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome back")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("\(viewModel.totalScans)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Total Scans")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(viewModel.subscriptionTier.rawValue.capitalized)
                        .font(.headline)
                        .foregroundColor(.accentColor)
                    Text("\(viewModel.scansRemaining ?? 0) scans left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var quickActionsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                QuickActionButton(
                    icon: "building.2",
                    title: "Exterior",
                    color: .green
                ) {
                    viewModel.startScan(mode: .exterior)
                }
                
                QuickActionButton(
                    icon: "house",
                    title: "Interior",
                    color: .blue
                ) {
                    viewModel.startScan(mode: .interior)
                }
                
                QuickActionButton(
                    icon: "cube",
                    title: "Object",
                    color: .orange
                ) {
                    viewModel.startScan(mode: .object)
                }
            }
            .padding()
        }
    }
    
    private var recentScansView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Scans")
                    .font(.headline)
                Spacer()
                NavigationLink("See All") {
                    LibraryView()
                }
                .font(.subheadline)
            }
            .padding(.horizontal)
            
            if viewModel.recentScans.isEmpty {
                EmptyStateView(
                    icon: "cube.transparent",
                    title: "No scans yet",
                    message: "Tap + to create your first 3D scan"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.recentScans) { scan in
                            NavigationLink(destination: ModelPreviewView(scan: scan)) {
                                ScanCard(scan: scan)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
    }
}
```

### Scan Screen
```swift
import SwiftUI
import ARKit
import RealityKit

struct ScanView: View {
    @StateObject private var viewModel: ScanViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(mode: ScanMode) {
        _viewModel = StateObject(wrappedValue: ScanViewModel(mode: mode))
    }
    
    var body: some View {
        ZStack {
            // AR View
            ARViewContainer(viewModel: viewModel)
                .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top bar
                topBar
                
                Spacer()
                
                // Quality indicator
                if viewModel.isScanning {
                    qualityIndicator
                }
                
                // Bottom controls
                bottomControls
            }
            
            // Processing overlay
            if viewModel.isProcessing {
                processingOverlay
            }
        }
        .onAppear {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }
    
    private var topBar: some View {
        HStack {
            Button("Cancel") {
                viewModel.cancel()
                dismiss()
            }
            .foregroundColor(.white)
            
            Spacer()
            
            // Scan info
            VStack {
                Text(viewModel.mode.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                if viewModel.isScanning {
                    Text(viewModel.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Settings
            Menu {
                Button("Quality: \(viewModel.quality.rawValue)") { }
                Toggle("HDR", isOn: $viewModel.hdrEnabled)
                Toggle("Flash", isOn: $viewModel.flashEnabled)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var qualityIndicator: some View {
        HStack(spacing: 20) {
            VStack {
                Text("\(viewModel.pointCount)")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Points")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.5))
            
            VStack {
                ProgressRing(progress: viewModel.coverage, color: .green)
                    .frame(width: 30, height: 30)
                Text("Coverage")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.5))
            
            VStack {
                Image(systemName: viewModel.trackingIcon)
                    .foregroundColor(viewModel.trackingColor)
                Text("Tracking")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 20)
    }
    
    private var bottomControls: some View {
        HStack(spacing: 40) {
            // Gallery
            Button {
                viewModel.showGallery()
            } label: {
                if let thumbnail = viewModel.lastThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .frame(width: 50, height: 50)
                        .foregroundColor(.white)
                }
            }
            
            // Capture button
            Button {
                if viewModel.isScanning {
                    viewModel.stopScanning()
                } else {
                    viewModel.startScanning()
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    if viewModel.isScanning {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 65, height: 65)
                    }
                }
            }
            
            // Mode info
            VStack {
                Image(systemName: viewModel.mode.icon)
                    .font(.title)
                    .foregroundColor(.white)
                Text(viewModel.mode.shortName)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: 50)
        }
        .padding(.vertical, 30)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }
    
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text("Processing scan...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("\(Int(viewModel.processingProgress * 100))%")
                    .font(.title)
                    .foregroundColor(.white)
                
                ProgressView(value: viewModel.processingProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.accentColor)
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ScanViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        viewModel.setupARView(arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) { }
}
```

### Export Screen
```swift
import SwiftUI

struct ExportView: View {
    let scan: Scan
    @StateObject private var viewModel: ExportViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(scan: Scan) {
        self.scan = scan
        _viewModel = StateObject(wrappedValue: ExportViewModel(scan: scan))
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Preview section
                Section {
                    ModelThumbnailView(scan: scan)
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                }
                
                // Format selection
                ForEach(ExportCategory.allCases, id: \.rawValue) { category in
                    Section(header: Text(category.rawValue)) {
                        ForEach(viewModel.formatsForCategory(category)) { format in
                            ExportFormatRow(
                                format: format,
                                isSelected: viewModel.selectedFormat == format,
                                isLocked: viewModel.isFormatLocked(format)
                            ) {
                                viewModel.selectFormat(format)
                            }
                        }
                    }
                }
                
                // Options
                Section(header: Text("Options")) {
                    Toggle("Include textures", isOn: $viewModel.includeTextures)
                    Toggle("Simplify mesh", isOn: $viewModel.simplifyMesh)
                    
                    if viewModel.simplifyMesh {
                        Stepper(
                            "Target: \(viewModel.targetFaceCount)k faces",
                            value: $viewModel.targetFaceCount,
                            in: 10...1000,
                            step: 10
                        )
                    }
                    
                    Picker("Coordinate system", selection: $viewModel.coordinateSystem) {
                        Text("Y-Up (Default)").tag(CoordinateSystem.yUp)
                        Text("Z-Up (CAD)").tag(CoordinateSystem.zUp)
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        viewModel.export()
                    }
                    .disabled(viewModel.selectedFormat == nil)
                }
            }
            .overlay {
                if viewModel.isExporting {
                    ExportProgressOverlay(progress: viewModel.exportProgress)
                }
            }
            .sheet(item: $viewModel.exportedFileURL) { url in
                ShareSheet(items: [url])
            }
        }
    }
}

struct ExportFormatRow: View {
    let format: ExportFormat
    let isSelected: Bool
    let isLocked: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading) {
                    Text(format.displayName)
                        .foregroundColor(isLocked ? .secondary : .primary)
                    
                    Text(".\(format.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isLocked {
                    Label("Pro", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .disabled(isLocked)
    }
}
```

---

## API ENDPOINTS

### REST API Specification
```yaml
openapi: 3.0.0
info:
  title: Lumiscan Cloud API
  version: 1.0.0

servers:
  - url: https://api.lumiscan.app/v1

paths:
  /auth/token:
    post:
      summary: Get authentication token
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                idToken:
                  type: string
                  description: Apple Sign In ID token
      responses:
        200:
          description: Authentication successful
          content:
            application/json:
              schema:
                type: object
                properties:
                  accessToken:
                    type: string
                  refreshToken:
                    type: string
                  expiresIn:
                    type: integer

  /scans:
    get:
      summary: List user's scans
      parameters:
        - name: limit
          in: query
          schema:
            type: integer
            default: 20
        - name: offset
          in: query
          schema:
            type: integer
            default: 0
      responses:
        200:
          description: List of scans
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Scan'
    
    post:
      summary: Create new scan
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                name:
                  type: string
                mode:
                  type: string
                  enum: [exterior, interior, object]
      responses:
        201:
          description: Scan created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Scan'

  /scans/{scanId}/upload-url:
    get:
      summary: Get presigned URL for upload
      parameters:
        - name: scanId
          in: path
          required: true
          schema:
            type: string
        - name: fileType
          in: query
          schema:
            type: string
            enum: [raw, mesh, pointcloud, texture]
      responses:
        200:
          description: Presigned URL
          content:
            application/json:
              schema:
                type: object
                properties:
                  uploadUrl:
                    type: string
                  expiresAt:
                    type: string
                    format: date-time

  /scans/{scanId}/process:
    post:
      summary: Start cloud processing
      parameters:
        - name: scanId
          in: path
          required: true
          schema:
            type: string
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ProcessingOptions'
      responses:
        202:
          description: Processing started
          content:
            application/json:
              schema:
                type: object
                properties:
                  jobId:
                    type: string
                  estimatedTime:
                    type: integer
                    description: Estimated time in seconds

  /jobs/{jobId}:
    get:
      summary: Get job status
      parameters:
        - name: jobId
          in: path
          required: true
          schema:
            type: string
      responses:
        200:
          description: Job status
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/JobStatus'
    
    delete:
      summary: Cancel job
      parameters:
        - name: jobId
          in: path
          required: true
          schema:
            type: string
      responses:
        204:
          description: Job cancelled

  /jobs/{jobId}/download:
    get:
      summary: Get download URLs for results
      parameters:
        - name: jobId
          in: path
          required: true
          schema:
            type: string
        - name: format
          in: query
          schema:
            type: string
      responses:
        200:
          description: Download URLs
          content:
            application/json:
              schema:
                type: object
                properties:
                  urls:
                    type: object
                    additionalProperties:
                      type: string

components:
  schemas:
    Scan:
      type: object
      properties:
        id:
          type: string
        name:
          type: string
        mode:
          type: string
        status:
          type: string
        createdAt:
          type: string
          format: date-time
        pointCount:
          type: integer
        faceCount:
          type: integer
        thumbnailUrl:
          type: string
    
    ProcessingOptions:
      type: object
      properties:
        quality:
          type: string
          enum: [standard, high, ultra]
        technologies:
          type: array
          items:
            type: string
            enum: [gaussianSplatting, nerf, nsr, photogrammetry]
        outputFormats:
          type: array
          items:
            type: string
        enableHoleFilling:
          type: boolean
        enableTextureEnhancement:
          type: boolean
    
    JobStatus:
      type: object
      properties:
        jobId:
          type: string
        status:
          type: string
          enum: [queued, processing, completed, failed, cancelled]
        progress:
          type: number
        estimatedTimeRemaining:
          type: integer
        error:
          type: string
        resultUrls:
          type: object
          additionalProperties:
            type: string
```

---

## TESTING CHECKLIST

### Unit Tests
```
[ ] LiDARService - session management
[ ] LiDARService - point cloud extraction
[ ] RoomPlanService - room capture
[ ] GaussianSplattingProcessor - initialization
[ ] GaussianSplattingProcessor - optimization
[ ] ExportService - all format exports
[ ] MeasurementService - distance calculation
[ ] MeasurementService - area calculation
[ ] CloudProcessingService - upload flow
[ ] CloudProcessingService - job status polling
[ ] SubscriptionService - tier validation
```

### Integration Tests
```
[ ] Full scan flow - Object mode
[ ] Full scan flow - Interior mode
[ ] Full scan flow - Exterior mode
[ ] Cloud processing round-trip
[ ] Export and share flow
[ ] Subscription purchase flow
[ ] iCloud sync
```

### UI Tests
```
[ ] Onboarding flow
[ ] New scan creation
[ ] Mode selection
[ ] Scan capture with quality indicator
[ ] Model preview and AR view
[ ] Measurement tool
[ ] Export format selection
[ ] Settings and subscription management
```

### Performance Tests
```
[ ] Memory usage during large scans (>1M points)
[ ] CPU/GPU usage during processing
[ ] Battery consumption during 10-min scan
[ ] Network bandwidth for cloud upload
[ ] Cold start time
[ ] Frame rate during AR preview
```

---

## DEPLOYMENT

### App Store Submission Checklist
```
[ ] App icons (all sizes)
[ ] Screenshots (all device sizes)
[ ] App preview video
[ ] Privacy policy URL
[ ] Terms of service URL
[ ] App description (EN, CZ, DE, FR, ES)
[ ] Keywords optimization
[ ] Age rating questionnaire
[ ] Export compliance
[ ] IDFA usage declaration
[ ] Camera usage description
[ ] Location usage description
[ ] LiDAR capability check
```

### CI/CD Pipeline
```yaml
# .github/workflows/main.yml
name: CI/CD

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '15.2'
      - name: Run tests
        run: |
          xcodebuild test \
            -scheme Lumiscan \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

  build:
    needs: test
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build archive
        run: |
          xcodebuild archive \
            -scheme Lumiscan \
            -archivePath Lumiscan.xcarchive \
            -configuration Release
      - name: Export IPA
        run: |
          xcodebuild -exportArchive \
            -archivePath Lumiscan.xcarchive \
            -exportPath ./build \
            -exportOptionsPlist ExportOptions.plist

  deploy-testflight:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: macos-14
    steps:
      - name: Upload to TestFlight
        run: |
          xcrun altool --upload-app \
            -f ./build/Lumiscan.ipa \
            -u ${{ secrets.APPLE_ID }} \
            -p ${{ secrets.APP_SPECIFIC_PASSWORD }}
```

---

## VERSION HISTORY

| Version | Date | Features |
|---------|------|----------|
| 1.0.0 | Q1 2026 | MVP - Basic scanning, Gaussian Splatting, core exports |
| 1.1.0 | Q2 2026 | Cloud processing, NeRF, NSR, CAD exports |
| 1.2.0 | Q3 2026 | Multi-room stitching, floor plans, PBR textures |
| 2.0.0 | Q4 2026 | Team features, API, Vision Pro support |

---

## CONTACTS

- **Product Owner:** [Name]
- **Tech Lead:** [Name]
- **iOS Developer:** [Name]
- **Backend Developer:** [Name]
- **Designer:** [Name]

---

*Document generated: January 2026*
*Last updated: v1.0*
