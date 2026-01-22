import Foundation
import RoomPlan
import simd
import Combine

// MARK: - RoomPlan Service Protocol

protocol RoomPlanServiceProtocol {
    var isSupported: Bool { get }
    var capturedRooms: AnyPublisher<[CapturedRoom], Never> { get }
    var scanProgress: AnyPublisher<Float, Never> { get }
    var captureStatus: AnyPublisher<RoomCaptureStatus, Never> { get }

    func startCapture() async throws
    func stopCapture() async -> CapturedStructure?
    func exportFloorPlan(structure: CapturedStructure) async throws -> URL
    func exportToUSDZ(structure: CapturedStructure) async throws -> URL
}

// MARK: - RoomPlan Capture Status

enum RoomCaptureStatus {
    case idle
    case preparing
    case capturing
    case processing
    case completed(CapturedStructure)
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

    static func == (lhs: RoomCaptureStatus, rhs: RoomCaptureStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.preparing, .preparing), (.capturing, .capturing), (.processing, .processing):
            return true
        case (.completed, .completed):
            return true // Comparing structure content would be expensive
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - RoomPlan Service

@MainActor
final class RoomPlanService: NSObject, RoomPlanServiceProtocol {

    static let shared = RoomPlanService()

    // MARK: - Properties

    private var roomCaptureSession: RoomCaptureSession?
    private var capturedStructure: CapturedStructure?
    private var roomCaptureView: RoomCaptureView?
    private var lastCapturedRoom: CapturedRoom?

    private let roomsSubject = PassthroughSubject<[CapturedRoom], Never>()
    private let progressSubject = PassthroughSubject<Float, Never>()
    private let statusSubject = CurrentValueSubject<RoomCaptureStatus, Never>(.idle)

    var isSupported: Bool {
        RoomCaptureSession.isSupported
    }

    var capturedRooms: AnyPublisher<[CapturedRoom], Never> {
        roomsSubject.eraseToAnyPublisher()
    }

    var scanProgress: AnyPublisher<Float, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    var captureStatus: AnyPublisher<RoomCaptureStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    var currentStatus: RoomCaptureStatus {
        statusSubject.value
    }

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Capture Control

    func startCapture() async throws {
        guard isSupported else {
            throw RoomPlanError.notSupported
        }

        statusSubject.send(.preparing)

        roomCaptureSession = RoomCaptureSession()
        roomCaptureSession?.delegate = self

        let config = RoomCaptureSession.Configuration()
        roomCaptureSession?.run(configuration: config)

        statusSubject.send(.capturing)
    }

    func stopCapture() async -> CapturedStructure? {
        statusSubject.send(.processing)
        roomCaptureSession?.stop()

        // Wait for processing to complete
        try? await Task.sleep(nanoseconds: 500_000_000)

        return capturedStructure
    }

    func cancelCapture() {
        roomCaptureSession?.stop()
        roomCaptureSession = nil
        capturedStructure = nil
        statusSubject.send(.idle)
    }

    // MARK: - Export Functions

    func exportFloorPlan(structure: CapturedStructure) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("floorplan_\(UUID().uuidString).usdz")

        try structure.export(to: tempURL)
        return tempURL
    }

    func exportToUSDZ(structure: CapturedStructure) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("room_\(UUID().uuidString).usdz")

        try structure.export(to: tempURL)
        return tempURL
    }

    // MARK: - Data Conversion

    func convertToScanSession(structure: CapturedStructure) -> ScanSession {
        let session = ScanSession(name: "RoomPlan Scan")

        // Convert rooms to point cloud and mesh
        var allVertices: [simd_float3] = []
        var allNormals: [simd_float3] = []
        var allFaces: [simd_uint3] = []
        var vertexOffset: UInt32 = 0

        for room in structure.rooms {
            // Add walls
            for wall in room.walls {
                let (vertices, normals, faces) = extractGeometry(from: wall)
                allVertices.append(contentsOf: vertices)
                allNormals.append(contentsOf: normals)
                allFaces.append(contentsOf: faces.map { simd_uint3($0.x + vertexOffset, $0.y + vertexOffset, $0.z + vertexOffset) })
                vertexOffset += UInt32(vertices.count)
            }

            // Add floors
            for floor in room.floors {
                let (vertices, normals, faces) = extractGeometry(from: floor)
                allVertices.append(contentsOf: vertices)
                allNormals.append(contentsOf: normals)
                allFaces.append(contentsOf: faces.map { simd_uint3($0.x + vertexOffset, $0.y + vertexOffset, $0.z + vertexOffset) })
                vertexOffset += UInt32(vertices.count)
            }

            // Add doors
            for door in room.doors {
                let (vertices, normals, faces) = extractGeometry(from: door)
                allVertices.append(contentsOf: vertices)
                allNormals.append(contentsOf: normals)
                allFaces.append(contentsOf: faces.map { simd_uint3($0.x + vertexOffset, $0.y + vertexOffset, $0.z + vertexOffset) })
                vertexOffset += UInt32(vertices.count)
            }

            // Add windows
            for window in room.windows {
                let (vertices, normals, faces) = extractGeometry(from: window)
                allVertices.append(contentsOf: vertices)
                allNormals.append(contentsOf: normals)
                allFaces.append(contentsOf: faces.map { simd_uint3($0.x + vertexOffset, $0.y + vertexOffset, $0.z + vertexOffset) })
                vertexOffset += UInt32(vertices.count)
            }
        }

        // Create combined mesh
        if !allVertices.isEmpty {
            let meshData = MeshData(
                anchorIdentifier: UUID(),
                vertices: allVertices,
                normals: allNormals,
                faces: allFaces
            )
            session.addMesh(meshData)
        }

        // Create point cloud from vertices
        let pointCloud = PointCloud(
            points: allVertices,
            colors: nil,
            normals: allNormals
        )
        session.pointCloud = pointCloud

        // Add room measurements
        for room in structure.rooms {
            // Add room area measurement
            let floorArea = calculateSurfaceArea(room: room)
            let areaMeasurement = Measurement(
                type: .area,
                points: [simd_float3.zero],
                value: Float(floorArea),
                unit: .meters,
                label: "Plocha místnosti"
            )
            session.addMeasurement(areaMeasurement)
        }

        return session
    }

    // MARK: - Geometry Extraction Helpers

    private func extractGeometry(from surface: CapturedRoom.Surface) -> ([simd_float3], [simd_float3], [simd_uint3]) {
        let transform = surface.transform
        let dimensions = surface.dimensions

        // Create a simple quad for the surface
        let halfWidth = dimensions.x / 2
        let halfHeight = dimensions.y / 2

        let localVertices: [simd_float3] = [
            simd_float3(-halfWidth, -halfHeight, 0),
            simd_float3(halfWidth, -halfHeight, 0),
            simd_float3(halfWidth, halfHeight, 0),
            simd_float3(-halfWidth, halfHeight, 0)
        ]

        // Transform vertices to world space
        let vertices = localVertices.map { vertex -> simd_float3 in
            let v4 = simd_float4(vertex.x, vertex.y, vertex.z, 1)
            let worldPos = transform * v4
            return simd_float3(worldPos.x, worldPos.y, worldPos.z)
        }

        // Calculate normal
        let edge1 = vertices[1] - vertices[0]
        let edge2 = vertices[3] - vertices[0]
        let normal = simd_normalize(simd_cross(edge1, edge2))
        let normals = [normal, normal, normal, normal]

        // Two triangles for the quad
        let faces: [simd_uint3] = [
            simd_uint3(0, 1, 2),
            simd_uint3(0, 2, 3)
        ]

        return (vertices, normals, faces)
    }

    private func calculateSurfaceArea(room: CapturedRoom) -> Double {
        var totalArea: Double = 0

        for floor in room.floors {
            let dimensions = floor.dimensions
            totalArea += Double(dimensions.x * dimensions.y)
        }

        return totalArea
    }

    // MARK: - Room Capture View

    func createCaptureView() -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        // Note: In newer iOS versions, captureSession is managed internally by the view
        // We configure the session separately and the view observes it
        self.roomCaptureView = view
        return view
    }
}

// MARK: - RoomCaptureSessionDelegate

extension RoomPlanService: RoomCaptureSessionDelegate {

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        Task { @MainActor in
            lastCapturedRoom = room
            roomsSubject.send([room])

            // Estimate progress based on coverage
            let wallCount = room.walls.count
            let doorCount = room.doors.count
            let windowCount = room.windows.count

            let estimatedProgress = min(Float(wallCount + doorCount + windowCount) / 20.0, 0.95)
            progressSubject.send(estimatedProgress)
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        Task { @MainActor in
            if let error = error {
                statusSubject.send(.failed(error.localizedDescription))
                return
            }

            // Build final structure from the last captured room
            do {
                let structureBuilder = StructureBuilder(options: [.beautifyObjects])

                // Use the last captured room to build structure
                if let room = lastCapturedRoom {
                    let structure = try await structureBuilder.capturedStructure(from: [room])
                    capturedStructure = structure
                    statusSubject.send(.completed(structure))
                } else {
                    statusSubject.send(.failed("Nepodařilo se získat data místnosti"))
                }
                progressSubject.send(1.0)
            } catch {
                statusSubject.send(.failed(error.localizedDescription))
            }
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
        Task { @MainActor in
            statusSubject.send(.capturing)
        }
    }
}

// Note: RoomCaptureViewDelegate is not used - we use RoomCaptureSessionDelegate instead
// which provides all necessary callbacks for capturing room data

// MARK: - Errors

enum RoomPlanError: LocalizedError {
    case notSupported
    case captureFailed
    case exportFailed
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "RoomPlan není na tomto zařízení podporován"
        case .captureFailed:
            return "Skenování místnosti selhalo"
        case .exportFailed:
            return "Export selhalo"
        case .processingFailed(let message):
            return "Zpracování selhalo: \(message)"
        }
    }
}

// MARK: - Room Statistics

struct RoomStatistics {
    let roomCount: Int
    let totalFloorArea: Float  // m²
    let totalWallArea: Float   // m²
    let wallCount: Int
    let doorCount: Int
    let windowCount: Int
    let objectCount: Int

    static func from(structure: CapturedStructure) -> RoomStatistics {
        var totalFloorArea: Float = 0
        var totalWallArea: Float = 0
        var wallCount = 0
        var doorCount = 0
        var windowCount = 0
        var objectCount = 0

        for room in structure.rooms {
            wallCount += room.walls.count
            doorCount += room.doors.count
            windowCount += room.windows.count
            objectCount += room.objects.count

            for floor in room.floors {
                totalFloorArea += floor.dimensions.x * floor.dimensions.y
            }

            for wall in room.walls {
                totalWallArea += wall.dimensions.x * wall.dimensions.y
            }
        }

        return RoomStatistics(
            roomCount: structure.rooms.count,
            totalFloorArea: totalFloorArea,
            totalWallArea: totalWallArea,
            wallCount: wallCount,
            doorCount: doorCount,
            windowCount: windowCount,
            objectCount: objectCount
        )
    }
}
