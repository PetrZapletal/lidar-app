import Foundation
import ARKit
import RoomPlan
import Combine
import simd

/// Adaptér pro interiérové skenování pomocí Apple RoomPlan API
///
/// Využívá `RoomCaptureSession` pro automatickou detekci stěn, dveří, oken
/// a dalších prvků místnosti. Konvertuje `CapturedRoom` na `MeshData`.
@MainActor
@Observable
final class RoomPlanScanningModeAdapter: NSObject, ScanningModeProtocol {

    // MARK: - ScanningModeProtocol Properties

    let mode: ScanMode = .interior

    var isAvailable: Bool {
        RoomCaptureSession.isSupported
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

    private let meshDataSubject = PassthroughSubject<MeshData, Never>()
    private let progressSubject = PassthroughSubject<Float, Never>()

    private var roomCaptureSession: RoomCaptureSession?
    private var capturedRoom: CapturedRoom?

    /// Průběžně sbírané mesh segmenty z RoomPlan updatů
    private var collectedMeshData: [MeshData] = []

    /// Počítadlo updatů pro výpočet progresu
    private var updateCount: Int = 0

    // MARK: - Initialization

    init(services: ServiceContainer) {
        self.services = services
        super.init()
        debugLog("RoomPlanScanningModeAdapter inicializován", category: .logCategoryScanning)
    }

    // MARK: - ScanningModeProtocol Methods

    func start() async throws {
        guard isAvailable else {
            errorLog("RoomPlan není na tomto zařízení podporován", category: .logCategoryScanning)
            throw ScanError.sessionFailed("RoomPlan není na tomto zařízení podporován")
        }

        // Vyčistit předchozí data
        collectedMeshData.removeAll()
        capturedRoom = nil
        updateCount = 0

        // Vytvořit a nakonfigurovat RoomCaptureSession
        let session = RoomCaptureSession()
        session.delegate = self
        self.roomCaptureSession = session

        // Konfigurace session
        let configuration = RoomCaptureSession.Configuration()
        session.run(configuration: configuration)

        isScanning = true
        trackingState = "Inicializace"

        debugLog("RoomPlan skenování zahájeno", category: .logCategoryScanning)
    }

    func pause() {
        guard isScanning else { return }

        // RoomCaptureSession nemá přímou pause metodu,
        // pozastavíme zastavením a uchováním stavu
        isScanning = false
        trackingState = "Pozastaveno"

        debugLog("RoomPlan skenování pozastaveno", category: .logCategoryScanning)
    }

    func resume() {
        guard !isScanning else { return }

        isScanning = true
        trackingState = "Skenování"

        debugLog("RoomPlan skenování obnoveno", category: .logCategoryScanning)
    }

    func stop() {
        roomCaptureSession?.stop()
        isScanning = false
        trackingState = "Zastaveno"

        debugLog(
            "RoomPlan skenování zastaveno, celkem \(collectedMeshData.count) mesh segmentů",
            category: .logCategoryScanning
        )
    }

    func getResults() -> ScanningModeResult {
        // Pokud máme finální CapturedRoom, konvertovat na mesh
        var finalMeshData = collectedMeshData

        if let room = capturedRoom {
            let roomMeshes = convertCapturedRoom(room)
            if !roomMeshes.isEmpty {
                finalMeshData = roomMeshes
            }
        }

        let totalVertices = finalMeshData.reduce(0) { $0 + $1.vertexCount }
        let totalFaces = finalMeshData.reduce(0) { $0 + $1.faceCount }

        // Metadata o detekovaných prvcích místnosti
        var metadata: [String: Any] = [
            "mode": ScanMode.interior.rawValue,
            "meshCount": finalMeshData.count,
            "totalVertices": totalVertices,
            "totalFaces": totalFaces
        ]

        if let room = capturedRoom {
            metadata["wallCount"] = room.walls.count
            metadata["doorCount"] = room.doors.count
            metadata["windowCount"] = room.windows.count
            metadata["openingCount"] = room.openings.count
        }

        debugLog(
            "Výsledky RoomPlan skenování: \(finalMeshData.count) meshů, \(totalVertices) vertexů",
            category: .logCategoryScanning
        )

        return ScanningModeResult(
            meshData: finalMeshData,
            pointCloud: nil,
            metadata: metadata
        )
    }

    // MARK: - CapturedRoom Conversion

    /// Konvertuje CapturedRoom surfaces na pole MeshData
    private func convertCapturedRoom(_ room: CapturedRoom) -> [MeshData] {
        var meshes: [MeshData] = []

        // Konvertovat stěny
        for wall in room.walls {
            if let mesh = convertSurfaceToMeshData(
                dimensions: wall.dimensions,
                transform: wall.transform,
                classification: .wall
            ) {
                meshes.append(mesh)
            }
        }

        // Konvertovat podlahu
        for floor in room.floors {
            if let mesh = convertSurfaceToMeshData(
                dimensions: floor.dimensions,
                transform: floor.transform,
                classification: .floor
            ) {
                meshes.append(mesh)
            }
        }

        // Konvertovat dveře
        for door in room.doors {
            if let mesh = convertSurfaceToMeshData(
                dimensions: door.dimensions,
                transform: door.transform,
                classification: .door
            ) {
                meshes.append(mesh)
            }
        }

        // Konvertovat okna
        for window in room.windows {
            if let mesh = convertSurfaceToMeshData(
                dimensions: window.dimensions,
                transform: window.transform,
                classification: .window
            ) {
                meshes.append(mesh)
            }
        }

        return meshes
    }

    /// Konvertuje plochu (dimensions + transform) na MeshData jako obdélníkový quad
    private func convertSurfaceToMeshData(
        dimensions: simd_float3,
        transform: simd_float4x4,
        classification: MeshClassification
    ) -> MeshData? {
        let halfWidth = dimensions.x / 2
        let halfHeight = dimensions.y / 2

        // Vytvořit quad ze 4 vertexů v lokálním prostoru
        let vertices: [simd_float3] = [
            simd_float3(-halfWidth, -halfHeight, 0),
            simd_float3( halfWidth, -halfHeight, 0),
            simd_float3( halfWidth,  halfHeight, 0),
            simd_float3(-halfWidth,  halfHeight, 0)
        ]

        // Normály směřující v Z směru (budou transformovány)
        let normals: [simd_float3] = [
            simd_float3(0, 0, 1),
            simd_float3(0, 0, 1),
            simd_float3(0, 0, 1),
            simd_float3(0, 0, 1)
        ]

        // Dva trojúhelníky pro quad
        let faces: [simd_uint3] = [
            simd_uint3(0, 1, 2),
            simd_uint3(0, 2, 3)
        ]

        let classifications: [UInt8] = Array(
            repeating: UInt8(classification.rawValue),
            count: vertices.count
        )

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces,
            classifications: classifications,
            transform: transform
        )
    }
}

// MARK: - RoomCaptureSessionDelegate

extension RoomPlanScanningModeAdapter: RoomCaptureSessionDelegate {

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didUpdate room: CapturedRoom
    ) {
        Task { @MainActor in
            self.updateCount += 1
            self.trackingState = "Skenování"
            self.capturedRoom = room

            // Konvertovat průběžný stav místnosti na mesh data
            let meshes = self.convertCapturedRoom(room)
            self.collectedMeshData = meshes

            // Odeslat poslední mesh přes publisher
            if let latestMesh = meshes.last {
                self.meshDataSubject.send(latestMesh)
            }

            // Odhadnout progress na základě počtu detekovaných ploch
            let surfaceCount = room.walls.count + room.floors.count + room.doors.count + room.windows.count
            let estimatedProgress = min(Float(surfaceCount) / 20.0, 0.95)
            self.progressSubject.send(estimatedProgress)

            debugLog(
                "RoomPlan update #\(self.updateCount): \(room.walls.count) stěn, \(room.doors.count) dveří, \(room.windows.count) oken",
                category: .logCategoryScanning
            )
        }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: (any Error)?
    ) {
        Task { @MainActor in
            if let error = error {
                errorLog(
                    "RoomPlan session skončila s chybou: \(error.localizedDescription)",
                    category: .logCategoryScanning
                )
                self.trackingState = "Chyba"
                self.isScanning = false
                return
            }

            // Použít poslední CapturedRoom z didUpdate callbacku jako finální výsledek.
            // CapturedRoomData slouží pro export (USDZ/PLY), ale finální geometrii
            // již máme z průběžných updatů.
            if let lastRoom = self.capturedRoom {
                let finalMeshes = self.convertCapturedRoom(lastRoom)
                self.collectedMeshData = finalMeshes

                // Odeslat všechny finální meshe
                for mesh in finalMeshes {
                    self.meshDataSubject.send(mesh)
                }

                debugLog(
                    "RoomPlan session dokončena: \(lastRoom.walls.count) stěn, \(lastRoom.doors.count) dveří",
                    category: .logCategoryScanning
                )
            }

            self.progressSubject.send(1.0)
            self.trackingState = "Dokončeno"

            self.isScanning = false
        }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didProvide instruction: RoomCaptureSession.Instruction
    ) {
        Task { @MainActor in
            let instructionText: String
            switch instruction {
            case .moveCloseToWall:
                instructionText = "Přibližte se ke stěně"
            case .moveAwayFromWall:
                instructionText = "Oddalte se od stěny"
            case .slowDown:
                instructionText = "Zpomalte pohyb"
            case .turnOnLight:
                instructionText = "Zapněte osvětlení"
            case .normal:
                instructionText = "Pokračujte ve skenování"
            case .lowTexture:
                instructionText = "Oblast s nízkou texturou"
            @unknown default:
                instructionText = "Pokračujte"
            }

            self.trackingState = instructionText

            debugLog(
                "RoomPlan instrukce: \(instructionText)",
                category: .logCategoryScanning
            )
        }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didStartWith configuration: RoomCaptureSession.Configuration
    ) {
        Task { @MainActor in
            self.trackingState = "Skenování zahájeno"
            debugLog("RoomPlan session zahájena", category: .logCategoryScanning)
        }
    }
}
