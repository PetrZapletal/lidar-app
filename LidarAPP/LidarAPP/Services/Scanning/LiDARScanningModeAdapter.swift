import Foundation
import ARKit
import Combine

/// Adaptér pro exteriérové skenování pomocí ARKit + LiDAR
///
/// Obaluje existující `ARSessionService` a konvertuje `ARMeshAnchor` na `MeshData`
/// pomocí `MeshAnchorProcessor`. Určený pro režim `.exterior` s `gravityAndHeading`.
@MainActor
@Observable
final class LiDARScanningModeAdapter: ScanningModeProtocol {

    // MARK: - ScanningModeProtocol Properties

    let mode: ScanMode = .exterior

    var isAvailable: Bool {
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

    /// Nasbíraná mesh data indexovaná podle anchor ID
    private var collectedMeshData: [UUID: MeshData] = [:]

    /// Počítadlo zpracovaných anchorů pro výpočet progresu
    private var processedAnchorCount: Int = 0

    // MARK: - Initialization

    init(services: ServiceContainer) {
        self.services = services
        debugLog("LiDARScanningModeAdapter inicializován", category: .logCategoryScanning)
    }

    // MARK: - ScanningModeProtocol Methods

    func start() async throws {
        guard isAvailable else {
            errorLog("LiDAR skenování není na tomto zařízení dostupné", category: .logCategoryScanning)
            throw ScanError.lidarNotAvailable
        }

        // Vyčistit předchozí data
        collectedMeshData.removeAll()
        processedAnchorCount = 0
        cancellables.removeAll()

        // Spustit AR session
        try services.arSession.startSession(mode: .exterior)
        isScanning = true

        // Napojit se na mesh anchory z AR session
        subscribeMeshAnchors()

        debugLog("LiDAR skenování zahájeno v exteriérovém režimu", category: .logCategoryScanning)
    }

    func pause() {
        guard isScanning else { return }

        services.arSession.pauseSession()
        isScanning = false

        debugLog("LiDAR skenování pozastaveno", category: .logCategoryScanning)
    }

    func resume() {
        guard !isScanning else { return }

        services.arSession.resumeSession()
        isScanning = true

        debugLog("LiDAR skenování obnoveno", category: .logCategoryScanning)
    }

    func stop() {
        services.arSession.stopSession()
        isScanning = false
        cancellables.removeAll()

        debugLog(
            "LiDAR skenování zastaveno, celkem \(collectedMeshData.count) mesh segmentů",
            category: .logCategoryScanning
        )
    }

    func getResults() -> ScanningModeResult {
        let meshArray = Array(collectedMeshData.values)

        // Vytvořit point cloud z vertexů všech meshů
        let allVertices = meshArray.flatMap { $0.worldVertices }
        let pointCloud: PointCloud? = allVertices.isEmpty ? nil : PointCloud(
            points: allVertices,
            metadata: PointCloudMetadata(source: .lidar)
        )

        let totalVertices = meshArray.reduce(0) { $0 + $1.vertexCount }
        let totalFaces = meshArray.reduce(0) { $0 + $1.faceCount }

        debugLog(
            "Výsledky LiDAR skenování: \(meshArray.count) meshů, \(totalVertices) vertexů, \(totalFaces) faces",
            category: .logCategoryScanning
        )

        return ScanningModeResult(
            meshData: meshArray,
            pointCloud: pointCloud,
            metadata: [
                "mode": ScanMode.exterior.rawValue,
                "meshCount": meshArray.count,
                "totalVertices": totalVertices,
                "totalFaces": totalFaces
            ]
        )
    }

    // MARK: - Private Methods

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

        processedAnchorCount += 1

        // Aktualizovat tracking state
        updateTrackingState()

        // Vypočítat a publikovat progress (estimace založená na počtu anchorů)
        let estimatedProgress = min(Float(collectedMeshData.count) / 100.0, 1.0)
        progressSubject.send(estimatedProgress)
    }

    /// Aktualizace textového popisu tracking stavu
    private func updateTrackingState() {
        guard let arTrackingState = services.arSession.trackingState else {
            trackingState = "Není dostupný"
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
            trackingState = "Normální"
        }
    }
}
