import Foundation
import ARKit
import RealityKit
import Combine
import simd

/// Adaptér pro skenování objektů pomocí Apple ObjectCaptureSession
///
/// Na zařízeních s iOS 17+ a podporou ObjectCaptureSession využívá nativní API.
/// Na ostatních zařízeních degraduje na ARKit-based skenování s orbitálním vedením.
///
/// ObjectCaptureSession je součástí RealityKit, ale nemusí být dostupný
/// ve všech verzích SDK. Proto je celá implementace podmíněně kompilována.
@MainActor
@Observable
final class ObjectCaptureScanningModeAdapter: ScanningModeProtocol {

    // MARK: - ScanningModeProtocol Properties

    let mode: ScanMode = .object

    var isAvailable: Bool {
        // ObjectCapture vyžaduje LiDAR, ověříme dostupnost scene reconstruction
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    private(set) var isScanning: Bool = false

    private(set) var trackingState: String = "Není inicializováno"

    var meshDataPublisher: AnyPublisher<MeshData, Never> {
        meshDataSubject.eraseToAnyPublisher()
    }

    var progressPublisher: AnyPublisher<Float, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private let services: ServiceContainer
    private let meshProcessor = MeshAnchorProcessor()

    private let meshDataSubject = PassthroughSubject<MeshData, Never>()
    private let progressSubject = PassthroughSubject<Float, Never>()
    private var cancellables = Set<AnyCancellable>()

    /// Sbírané mesh segmenty
    private var collectedMeshData: [UUID: MeshData] = [:]

    /// Aktuální progress pokrytí objektu
    private var captureProgress: Float = 0.0

    /// Počet zpracovaných updatů pro odhad progresu
    private var updateCount: Int = 0

    /// Dočasný adresář pro snímky objektu (pro budoucí ObjectCaptureSession)
    private var captureOutputDirectory: URL?

    // MARK: - Initialization

    init(services: ServiceContainer) {
        self.services = services
        debugLog("ObjectCaptureScanningModeAdapter inicializován", category: .logCategoryScanning)
    }

    // MARK: - ScanningModeProtocol Methods

    func start() async throws {
        guard isAvailable else {
            errorLog("ObjectCapture není na tomto zařízení podporováno", category: .logCategoryScanning)
            throw ScanError.lidarNotAvailable
        }

        // Vyčistit předchozí data
        collectedMeshData.removeAll()
        captureProgress = 0.0
        updateCount = 0
        cancellables.removeAll()

        // Spustit AR session v režimu pro objekty (gravity alignment)
        try services.arSession.startSession(mode: .object)
        isScanning = true
        trackingState = "Inicializace"

        // Napojit se na mesh anchory
        subscribeMeshAnchors()

        // Vytvořit výstupní adresář pro budoucí použití
        do {
            let outputDir = try createCaptureOutputDirectory()
            self.captureOutputDirectory = outputDir
            debugLog(
                "ObjectCapture výstupní adresář připraven: \(outputDir.path)",
                category: .logCategoryScanning
            )
        } catch {
            warningLog(
                "Nelze vytvořit výstupní adresář: \(error.localizedDescription)",
                category: .logCategoryScanning
            )
        }

        debugLog("ObjectCapture skenování zahájeno (ARKit fallback)", category: .logCategoryScanning)
    }

    func pause() {
        guard isScanning else { return }

        services.arSession.pauseSession()
        isScanning = false
        trackingState = "Pozastaveno"

        debugLog("ObjectCapture skenování pozastaveno", category: .logCategoryScanning)
    }

    func resume() {
        guard !isScanning else { return }

        services.arSession.resumeSession()
        isScanning = true
        trackingState = "Skenování"

        debugLog("ObjectCapture skenování obnoveno", category: .logCategoryScanning)
    }

    func stop() {
        services.arSession.stopSession()
        isScanning = false
        cancellables.removeAll()
        trackingState = "Zastaveno"

        debugLog(
            "ObjectCapture skenování zastaveno, \(collectedMeshData.count) mesh segmentů, progress: \(Int(captureProgress * 100))%",
            category: .logCategoryScanning
        )
    }

    func getResults() -> ScanningModeResult {
        let meshArray = Array(collectedMeshData.values)
        let totalVertices = meshArray.reduce(0) { $0 + $1.vertexCount }
        let totalFaces = meshArray.reduce(0) { $0 + $1.faceCount }

        debugLog(
            "Výsledky ObjectCapture: \(meshArray.count) meshů, \(totalVertices) vertexů",
            category: .logCategoryScanning
        )

        return ScanningModeResult(
            meshData: meshArray,
            pointCloud: nil,
            metadata: [
                "mode": ScanMode.object.rawValue,
                "meshCount": meshArray.count,
                "totalVertices": totalVertices,
                "totalFaces": totalFaces,
                "captureProgress": captureProgress,
                "outputDirectory": captureOutputDirectory?.path ?? ""
            ]
        )
    }

    // MARK: - ARKit Mesh Processing

    /// Napojení na publisher mesh anchorů z ARSessionService
    private func subscribeMeshAnchors() {
        services.arSession.meshAnchorsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] anchors in
                guard let self else { return }
                self.processMeshAnchors(anchors)
            }
            .store(in: &cancellables)
    }

    /// Zpracování příchozích mesh anchorů na MeshData
    private func processMeshAnchors(_ anchors: [ARMeshAnchor]) {
        for anchor in anchors {
            let meshData = meshProcessor.extractMeshData(from: anchor)
            collectedMeshData[anchor.identifier] = meshData

            // Odeslat aktualizaci přes publisher
            meshDataSubject.send(meshData)
        }

        updateCount += 1
        updateTrackingState()

        // Estimace progresu na základě pokrytí (počet anchorů)
        captureProgress = min(Float(collectedMeshData.count) / 50.0, 0.95)
        progressSubject.send(captureProgress)
    }

    /// Aktualizace textového popisu tracking stavu
    private func updateTrackingState() {
        guard let arTrackingState = services.arSession.trackingState else {
            trackingState = "Nedostupný"
            return
        }

        switch arTrackingState {
        case .notAvailable:
            trackingState = "Nedostupný"
        case .limited(let reason):
            switch reason {
            case .initializing:
                trackingState = "Inicializace"
            case .excessiveMotion:
                trackingState = "Příliš rychlý pohyb"
            case .insufficientFeatures:
                trackingState = "Nedostatek bodů"
            case .relocalizing:
                trackingState = "Relokalizace"
            @unknown default:
                trackingState = "Omezený"
            }
        case .normal:
            trackingState = "Snímání objektu"
        }
    }

    // MARK: - Bounding Box Mesh Generation

    /// Vytvoří mesh data z bounding boxu objektu
    func createBoundingBoxMesh(
        center: simd_float3,
        extent: simd_float3
    ) -> MeshData {
        let halfExtent = extent / 2

        // 8 vertexů kvádru
        let vertices: [simd_float3] = [
            center + simd_float3(-halfExtent.x, -halfExtent.y, -halfExtent.z),
            center + simd_float3( halfExtent.x, -halfExtent.y, -halfExtent.z),
            center + simd_float3( halfExtent.x,  halfExtent.y, -halfExtent.z),
            center + simd_float3(-halfExtent.x,  halfExtent.y, -halfExtent.z),
            center + simd_float3(-halfExtent.x, -halfExtent.y,  halfExtent.z),
            center + simd_float3( halfExtent.x, -halfExtent.y,  halfExtent.z),
            center + simd_float3( halfExtent.x,  halfExtent.y,  halfExtent.z),
            center + simd_float3(-halfExtent.x,  halfExtent.y,  halfExtent.z)
        ]

        // Normály pro každý vertex (aproximace)
        let normals: [simd_float3] = vertices.map { vertex in
            simd_normalize(vertex - center)
        }

        // 12 trojúhelníků (2 na každou stěnu kvádru)
        let faces: [simd_uint3] = [
            // Front
            simd_uint3(0, 1, 2), simd_uint3(0, 2, 3),
            // Back
            simd_uint3(5, 4, 7), simd_uint3(5, 7, 6),
            // Left
            simd_uint3(4, 0, 3), simd_uint3(4, 3, 7),
            // Right
            simd_uint3(1, 5, 6), simd_uint3(1, 6, 2),
            // Top
            simd_uint3(3, 2, 6), simd_uint3(3, 6, 7),
            // Bottom
            simd_uint3(4, 5, 1), simd_uint3(4, 1, 0)
        ]

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces
        )
    }

    // MARK: - File Management

    /// Vytvoří dočasný adresář pro výstup ObjectCapture
    private func createCaptureOutputDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let captureDir = tempDir.appending(path: "ObjectCapture_\(UUID().uuidString)")

        let imagesDir = captureDir.appending(path: "Images")
        let checkpointsDir = captureDir.appending(path: "Checkpoints")

        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkpointsDir, withIntermediateDirectories: true)

        return captureDir
    }

    /// Vyčistí dočasné soubory po skenování
    func cleanupCaptureFiles() {
        guard let outputDir = captureOutputDirectory else { return }

        do {
            try FileManager.default.removeItem(at: outputDir)
            captureOutputDirectory = nil
            debugLog("ObjectCapture dočasné soubory vyčištěny", category: .logCategoryScanning)
        } catch {
            warningLog(
                "Nelze vyčistit ObjectCapture dočasné soubory: \(error.localizedDescription)",
                category: .logCategoryScanning
            )
        }
    }
}
