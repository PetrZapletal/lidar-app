import XCTest
import simd
@testable import LidarAPP

final class MeshDataTests: XCTestCase {

    // MARK: - Initialization Tests

    func testMeshDataInitialization() {
        // Given
        let vertices: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(1, 0, 0),
            simd_float3(0, 1, 0)
        ]
        let normals: [simd_float3] = [
            simd_float3(0, 0, 1),
            simd_float3(0, 0, 1),
            simd_float3(0, 0, 1)
        ]
        let faces: [simd_uint3] = [
            simd_uint3(0, 1, 2)
        ]

        // When
        let mesh = MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces
        )

        // Then
        XCTAssertEqual(mesh.vertexCount, 3)
        XCTAssertEqual(mesh.faceCount, 1)
        XCTAssertEqual(mesh.triangleCount, 1)
    }

    // MARK: - Surface Area Tests

    func testTriangleSurfaceArea() {
        // Given - Right triangle with legs of 1 and 1, area = 0.5
        let vertices: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(1, 0, 0),
            simd_float3(0, 1, 0)
        ]
        let normals: [simd_float3] = [
            simd_float3(0, 0, 1),
            simd_float3(0, 0, 1),
            simd_float3(0, 0, 1)
        ]
        let faces: [simd_uint3] = [simd_uint3(0, 1, 2)]

        // When
        let mesh = MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces
        )

        // Then
        XCTAssertEqual(Double(mesh.surfaceArea), 0.5, accuracy: 0.001)
    }

    func testSquareSurfaceArea() {
        // Given - Unit square made of two triangles, area = 1.0
        let vertices: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(1, 0, 0),
            simd_float3(1, 1, 0),
            simd_float3(0, 1, 0)
        ]
        let normals = [simd_float3](repeating: simd_float3(0, 0, 1), count: 4)
        let faces: [simd_uint3] = [
            simd_uint3(0, 1, 2),
            simd_uint3(0, 2, 3)
        ]

        // When
        let mesh = MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces
        )

        // Then
        XCTAssertEqual(Double(mesh.surfaceArea), 1.0, accuracy: 0.001)
    }

    // MARK: - Bounding Box Tests

    func testMeshBoundingBox() {
        // Given
        let vertices: [simd_float3] = [
            simd_float3(-1, -2, -3),
            simd_float3(4, 5, 6),
            simd_float3(0, 0, 0)
        ]
        let normals = [simd_float3](repeating: simd_float3(0, 0, 1), count: 3)
        let faces: [simd_uint3] = [simd_uint3(0, 1, 2)]

        // When
        let mesh = MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces
        )
        let bbox = mesh.boundingBox

        // Then
        XCTAssertNotNil(bbox)
        XCTAssertEqual(Double(bbox?.min.x ?? 0), -1, accuracy: 0.001)
        XCTAssertEqual(Double(bbox?.min.y ?? 0), -2, accuracy: 0.001)
        XCTAssertEqual(Double(bbox?.min.z ?? 0), -3, accuracy: 0.001)
        XCTAssertEqual(Double(bbox?.max.x ?? 0), 4, accuracy: 0.001)
        XCTAssertEqual(Double(bbox?.max.y ?? 0), 5, accuracy: 0.001)
        XCTAssertEqual(Double(bbox?.max.z ?? 0), 6, accuracy: 0.001)
    }

    func testEmptyMeshBoundingBox() {
        // Given
        let mesh = MeshData(
            anchorIdentifier: UUID(),
            vertices: [],
            normals: [],
            faces: []
        )

        // Then
        XCTAssertNil(mesh.boundingBox)
    }

    // MARK: - World Vertices Tests

    func testWorldVerticesWithIdentityTransform() {
        // Given
        let vertices: [simd_float3] = [
            simd_float3(1, 2, 3)
        ]
        let mesh = MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: [simd_float3(0, 0, 1)],
            faces: []
        )

        // When
        let worldVerts = mesh.worldVertices

        // Then
        XCTAssertEqual(Double(worldVerts[0].x), 1, accuracy: 0.001)
        XCTAssertEqual(Double(worldVerts[0].y), 2, accuracy: 0.001)
        XCTAssertEqual(Double(worldVerts[0].z), 3, accuracy: 0.001)
    }

    func testWorldVerticesWithTranslation() {
        // Given
        let vertices: [simd_float3] = [simd_float3(0, 0, 0)]
        var transform = matrix_identity_float4x4
        transform.columns.3 = simd_float4(5, 10, 15, 1)

        let mesh = MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: [simd_float3(0, 0, 1)],
            faces: [],
            transform: transform
        )

        // When
        let worldVerts = mesh.worldVertices

        // Then
        XCTAssertEqual(Double(worldVerts[0].x), 5, accuracy: 0.001)
        XCTAssertEqual(Double(worldVerts[0].y), 10, accuracy: 0.001)
        XCTAssertEqual(Double(worldVerts[0].z), 15, accuracy: 0.001)
    }
}

// MARK: - CombinedMesh Tests

final class CombinedMeshTests: XCTestCase {

    func testAddMesh() {
        // Given
        let combinedMesh = CombinedMesh()
        let mesh = createSampleMesh(vertexCount: 3, faceCount: 1)

        // When
        combinedMesh.addOrUpdate(mesh)

        // Then
        XCTAssertEqual(combinedMesh.meshes.count, 1)
        XCTAssertEqual(combinedMesh.totalVertexCount, 3)
        XCTAssertEqual(combinedMesh.totalFaceCount, 1)
    }

    func testUpdateMesh() {
        // Given
        let combinedMesh = CombinedMesh()
        let anchorId = UUID()
        let mesh1 = createSampleMesh(anchorId: anchorId, vertexCount: 3, faceCount: 1)
        let mesh2 = createSampleMesh(anchorId: anchorId, vertexCount: 6, faceCount: 2)

        // When
        combinedMesh.addOrUpdate(mesh1)
        combinedMesh.addOrUpdate(mesh2)

        // Then - should have updated, not added
        XCTAssertEqual(combinedMesh.meshes.count, 1)
        XCTAssertEqual(combinedMesh.totalVertexCount, 6)
        XCTAssertEqual(combinedMesh.totalFaceCount, 2)
    }

    func testRemoveMesh() {
        // Given
        let combinedMesh = CombinedMesh()
        let anchorId = UUID()
        let mesh = createSampleMesh(anchorId: anchorId, vertexCount: 3, faceCount: 1)
        combinedMesh.addOrUpdate(mesh)

        // When
        combinedMesh.remove(identifier: anchorId)

        // Then
        XCTAssertEqual(combinedMesh.meshes.count, 0)
    }

    func testClear() {
        // Given
        let combinedMesh = CombinedMesh()
        combinedMesh.addOrUpdate(createSampleMesh(vertexCount: 3, faceCount: 1))
        combinedMesh.addOrUpdate(createSampleMesh(vertexCount: 3, faceCount: 1))

        // When
        combinedMesh.clear()

        // Then
        XCTAssertEqual(combinedMesh.meshes.count, 0)
    }

    func testToUnifiedMesh() {
        // Given
        let combinedMesh = CombinedMesh()
        combinedMesh.addOrUpdate(createSampleMesh(vertexCount: 3, faceCount: 1))
        combinedMesh.addOrUpdate(createSampleMesh(vertexCount: 4, faceCount: 2))

        // When
        let unified = combinedMesh.toUnifiedMesh()

        // Then
        XCTAssertNotNil(unified)
        XCTAssertEqual(unified?.vertexCount, 7)
        XCTAssertEqual(unified?.faceCount, 3)
    }

    func testEmptyCombinedMesh() {
        // Given
        let combinedMesh = CombinedMesh()

        // Then
        XCTAssertNil(combinedMesh.toUnifiedMesh())
        XCTAssertEqual(combinedMesh.totalVertexCount, 0)
        XCTAssertEqual(combinedMesh.totalFaceCount, 0)
    }

    // MARK: - Helper

    private func createSampleMesh(
        anchorId: UUID = UUID(),
        vertexCount: Int,
        faceCount: Int
    ) -> MeshData {
        let vertices = [simd_float3](repeating: simd_float3(0, 0, 0), count: vertexCount)
        let normals = [simd_float3](repeating: simd_float3(0, 0, 1), count: vertexCount)
        let faces = [simd_uint3](repeating: simd_uint3(0, 1, 2), count: faceCount)

        return MeshData(
            anchorIdentifier: anchorId,
            vertices: vertices,
            normals: normals,
            faces: faces
        )
    }
}

// MARK: - MeshClassification Tests

final class MeshClassificationTests: XCTestCase {

    func testAllCasesHaveDisplayNames() {
        for classification in MeshClassification.allCases {
            XCTAssertFalse(classification.displayName.isEmpty)
        }
    }

    func testAllCasesHaveColors() {
        for classification in MeshClassification.allCases {
            let color = classification.color
            XCTAssertEqual(Double(color.w), 1.0, accuracy: 0.001, "Alpha should be 1.0")
        }
    }

    func testRawValues() {
        XCTAssertEqual(MeshClassification.none.rawValue, 0)
        XCTAssertEqual(MeshClassification.wall.rawValue, 1)
        XCTAssertEqual(MeshClassification.floor.rawValue, 2)
        XCTAssertEqual(MeshClassification.ceiling.rawValue, 3)
        XCTAssertEqual(MeshClassification.table.rawValue, 4)
        XCTAssertEqual(MeshClassification.seat.rawValue, 5)
        XCTAssertEqual(MeshClassification.window.rawValue, 6)
        XCTAssertEqual(MeshClassification.door.rawValue, 7)
    }
}
