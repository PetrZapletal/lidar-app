import Foundation
import simd
import ARKit

/// Represents 3D mesh data extracted from LiDAR scanning
struct MeshData: Identifiable, Sendable {
    let id: UUID
    let anchorIdentifier: UUID  // ARMeshAnchor identifier
    let vertices: [simd_float3]
    let normals: [simd_float3]
    let faces: [simd_uint3]  // Triangle indices
    let textureCoordinates: [simd_float2]?
    let classifications: [UInt8]?  // ARMeshClassification raw values
    let transform: simd_float4x4
    let createdAt: Date

    init(
        id: UUID = UUID(),
        anchorIdentifier: UUID,
        vertices: [simd_float3],
        normals: [simd_float3],
        faces: [simd_uint3],
        textureCoordinates: [simd_float2]? = nil,
        classifications: [UInt8]? = nil,
        transform: simd_float4x4 = matrix_identity_float4x4
    ) {
        self.id = id
        self.anchorIdentifier = anchorIdentifier
        self.vertices = vertices
        self.normals = normals
        self.faces = faces
        self.textureCoordinates = textureCoordinates
        self.classifications = classifications
        self.transform = transform
        self.createdAt = Date()
    }

    // MARK: - Computed Properties

    var vertexCount: Int { vertices.count }
    var faceCount: Int { faces.count }
    var triangleCount: Int { faces.count }

    var boundingBox: BoundingBox? {
        guard !vertices.isEmpty else { return nil }

        var minPoint = vertices[0]
        var maxPoint = vertices[0]

        for vertex in vertices {
            minPoint = simd_min(minPoint, vertex)
            maxPoint = simd_max(maxPoint, vertex)
        }

        return BoundingBox(min: minPoint, max: maxPoint)
    }

    // MARK: - Surface Area Calculation

    var surfaceArea: Float {
        faces.reduce(0) { total, face in
            let v0 = vertices[Int(face.x)]
            let v1 = vertices[Int(face.y)]
            let v2 = vertices[Int(face.z)]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let cross = simd_cross(edge1, edge2)

            return total + simd_length(cross) / 2
        }
    }

    // MARK: - Volume Calculation (Signed Volume Method)

    var volume: Float {
        faces.reduce(0) { total, face in
            let v0 = vertices[Int(face.x)]
            let v1 = vertices[Int(face.y)]
            let v2 = vertices[Int(face.z)]

            // Signed volume of tetrahedron with origin
            let signedVolume = simd_dot(v0, simd_cross(v1, v2)) / 6.0
            return total + signedVolume
        }
    }

    // MARK: - World Space Vertices

    var worldVertices: [simd_float3] {
        vertices.map { vertex in
            let worldPosition = transform * simd_float4(vertex, 1)
            return simd_float3(worldPosition.x, worldPosition.y, worldPosition.z)
        }
    }
}

// MARK: - Combined Mesh

/// Manages multiple mesh anchors as a unified mesh
@Observable
final class CombinedMesh: @unchecked Sendable {
    private(set) var meshes: [UUID: MeshData] = [:]

    var totalVertexCount: Int {
        meshes.values.reduce(0) { $0 + $1.vertexCount }
    }

    var totalFaceCount: Int {
        meshes.values.reduce(0) { $0 + $1.faceCount }
    }

    var totalSurfaceArea: Float {
        meshes.values.reduce(0) { $0 + $1.surfaceArea }
    }

    func addOrUpdate(_ mesh: MeshData) {
        meshes[mesh.anchorIdentifier] = mesh
    }

    func remove(identifier: UUID) {
        meshes.removeValue(forKey: identifier)
    }

    func clear() {
        meshes.removeAll()
    }

    /// Combine all meshes into a single unified mesh
    func toUnifiedMesh() -> MeshData? {
        guard !meshes.isEmpty else { return nil }

        var allVertices: [simd_float3] = []
        var allNormals: [simd_float3] = []
        var allFaces: [simd_uint3] = []

        var vertexOffset: UInt32 = 0

        for mesh in meshes.values {
            // Add world-space vertices
            allVertices.append(contentsOf: mesh.worldVertices)
            allNormals.append(contentsOf: mesh.normals)

            // Offset face indices
            let offsetFaces = mesh.faces.map { face in
                simd_uint3(
                    face.x + vertexOffset,
                    face.y + vertexOffset,
                    face.z + vertexOffset
                )
            }
            allFaces.append(contentsOf: offsetFaces)

            vertexOffset += UInt32(mesh.vertices.count)
        }

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: allVertices,
            normals: allNormals,
            faces: allFaces
        )
    }
}

// MARK: - Mesh Classification Helper

enum MeshClassification: Int, CaseIterable, Sendable {
    case none = 0
    case wall = 1
    case floor = 2
    case ceiling = 3
    case table = 4
    case seat = 5
    case window = 6
    case door = 7

    var displayName: String {
        switch self {
        case .none: return "Unknown"
        case .wall: return "Wall"
        case .floor: return "Floor"
        case .ceiling: return "Ceiling"
        case .table: return "Table"
        case .seat: return "Seat"
        case .window: return "Window"
        case .door: return "Door"
        }
    }

    var color: simd_float4 {
        switch self {
        case .none: return simd_float4(0.5, 0.5, 0.5, 1)
        case .wall: return simd_float4(0.8, 0.8, 0.9, 1)
        case .floor: return simd_float4(0.6, 0.4, 0.2, 1)
        case .ceiling: return simd_float4(0.9, 0.9, 0.95, 1)
        case .table: return simd_float4(0.6, 0.3, 0.1, 1)
        case .seat: return simd_float4(0.2, 0.5, 0.8, 1)
        case .window: return simd_float4(0.7, 0.9, 1.0, 1)
        case .door: return simd_float4(0.5, 0.3, 0.1, 1)
        }
    }
}
