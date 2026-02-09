import ARKit
import simd

/// Processes ARMeshAnchor to extract mesh data (vertices, normals, faces, classification)
final class MeshAnchorProcessor: Sendable {

    // MARK: - Mesh Data Extraction

    /// Extract complete mesh data from an ARMeshAnchor
    func extractMeshData(from anchor: ARMeshAnchor) -> MeshData {
        let geometry = anchor.geometry

        let vertices = extractVertices(from: geometry)
        let normals = extractNormals(from: geometry)
        let faces = extractFaces(from: geometry)
        let classifications = extractClassifications(from: geometry)

        return MeshData(
            anchorIdentifier: anchor.identifier,
            vertices: vertices,
            normals: normals,
            faces: faces,
            classifications: classifications,
            transform: anchor.transform
        )
    }

    /// Extract mesh data with world-space transformation applied
    func extractWorldSpaceMeshData(from anchor: ARMeshAnchor) -> MeshData {
        let geometry = anchor.geometry

        let localVertices = extractVertices(from: geometry)
        let worldVertices = localVertices.map { vertex -> simd_float3 in
            let worldPosition = anchor.transform * simd_float4(vertex, 1)
            return simd_float3(worldPosition.x, worldPosition.y, worldPosition.z)
        }

        let localNormals = extractNormals(from: geometry)
        let normalMatrix = simd_float3x3(
            simd_float3(anchor.transform[0].x, anchor.transform[0].y, anchor.transform[0].z),
            simd_float3(anchor.transform[1].x, anchor.transform[1].y, anchor.transform[1].z),
            simd_float3(anchor.transform[2].x, anchor.transform[2].y, anchor.transform[2].z)
        )
        let worldNormals = localNormals.map { simd_normalize(normalMatrix * $0) }

        let faces = extractFaces(from: geometry)
        let classifications = extractClassifications(from: geometry)

        return MeshData(
            anchorIdentifier: anchor.identifier,
            vertices: worldVertices,
            normals: worldNormals,
            faces: faces,
            classifications: classifications,
            transform: matrix_identity_float4x4
        )
    }

    // MARK: - Vertex Extraction

    private func extractVertices(from geometry: ARMeshGeometry) -> [simd_float3] {
        let vertexBuffer = geometry.vertices
        let vertexCount = vertexBuffer.count

        var vertices: [simd_float3] = []
        vertices.reserveCapacity(vertexCount)

        let stride = vertexBuffer.stride
        let offset = vertexBuffer.offset

        vertexBuffer.buffer.contents().withMemoryRebound(to: UInt8.self, capacity: vertexBuffer.buffer.length) { pointer in
            for i in 0..<vertexCount {
                let vertexPointer = pointer.advanced(by: offset + i * stride)
                let vertex = vertexPointer.withMemoryRebound(to: simd_float3.self, capacity: 1) { $0.pointee }
                vertices.append(vertex)
            }
        }

        return vertices
    }

    // MARK: - Normal Extraction

    private func extractNormals(from geometry: ARMeshGeometry) -> [simd_float3] {
        let normalBuffer = geometry.normals
        let normalCount = normalBuffer.count

        var normals: [simd_float3] = []
        normals.reserveCapacity(normalCount)

        let stride = normalBuffer.stride
        let offset = normalBuffer.offset

        normalBuffer.buffer.contents().withMemoryRebound(to: UInt8.self, capacity: normalBuffer.buffer.length) { pointer in
            for i in 0..<normalCount {
                let normalPointer = pointer.advanced(by: offset + i * stride)
                let normal = normalPointer.withMemoryRebound(to: simd_float3.self, capacity: 1) { $0.pointee }
                normals.append(normal)
            }
        }

        return normals
    }

    // MARK: - Face Extraction

    private func extractFaces(from geometry: ARMeshGeometry) -> [simd_uint3] {
        let faceBuffer = geometry.faces
        let faceCount = faceBuffer.count

        var faces: [simd_uint3] = []
        faces.reserveCapacity(faceCount)

        let bytesPerIndex = faceBuffer.bytesPerIndex
        let indicesPerFace = faceBuffer.indexCountPerPrimitive
        let buffer = faceBuffer.buffer.contents()

        for i in 0..<faceCount {
            let offset = i * indicesPerFace * bytesPerIndex

            let indices: [UInt32]
            if bytesPerIndex == 4 {
                let pointer = (buffer + offset).bindMemory(to: UInt32.self, capacity: indicesPerFace)
                indices = [pointer[0], pointer[1], pointer[2]]
            } else {
                let pointer = (buffer + offset).bindMemory(to: UInt16.self, capacity: indicesPerFace)
                indices = [UInt32(pointer[0]), UInt32(pointer[1]), UInt32(pointer[2])]
            }

            faces.append(simd_uint3(indices[0], indices[1], indices[2]))
        }

        return faces
    }

    // MARK: - Classification Extraction

    private func extractClassifications(from geometry: ARMeshGeometry) -> [UInt8]? {
        guard let classificationBuffer = geometry.classification else { return nil }

        let count = classificationBuffer.count
        var classifications: [UInt8] = []
        classifications.reserveCapacity(count)

        let stride = classificationBuffer.stride
        let offset = classificationBuffer.offset

        classificationBuffer.buffer.contents().withMemoryRebound(to: UInt8.self, capacity: classificationBuffer.buffer.length) { pointer in
            for i in 0..<count {
                let value = pointer[offset + i * stride]
                classifications.append(value)
            }
        }

        return classifications
    }

    // MARK: - Statistics

    struct MeshStatistics {
        let vertexCount: Int
        let faceCount: Int
        let surfaceArea: Float
        let boundingBox: BoundingBox?
        let classificationCounts: [MeshClassification: Int]
    }

    func computeStatistics(from anchor: ARMeshAnchor) -> MeshStatistics {
        let meshData = extractMeshData(from: anchor)

        var classificationCounts: [MeshClassification: Int] = [:]
        if let classifications = meshData.classifications {
            for rawValue in classifications {
                if let classification = MeshClassification(rawValue: Int(rawValue)) {
                    classificationCounts[classification, default: 0] += 1
                }
            }
        }

        return MeshStatistics(
            vertexCount: meshData.vertexCount,
            faceCount: meshData.faceCount,
            surfaceArea: meshData.surfaceArea,
            boundingBox: meshData.boundingBox,
            classificationCounts: classificationCounts
        )
    }
}

// MARK: - Batch Processing

extension MeshAnchorProcessor {

    /// Process multiple mesh anchors in parallel
    func processMeshAnchors(_ anchors: [ARMeshAnchor]) async -> [MeshData] {
        await withTaskGroup(of: MeshData.self) { group in
            for anchor in anchors {
                group.addTask {
                    self.extractMeshData(from: anchor)
                }
            }

            var results: [MeshData] = []
            for await mesh in group {
                results.append(mesh)
            }
            return results
        }
    }

    /// Combine multiple mesh data into a single unified mesh
    func combineMeshes(_ meshes: [MeshData]) -> MeshData? {
        guard !meshes.isEmpty else { return nil }

        var allVertices: [simd_float3] = []
        var allNormals: [simd_float3] = []
        var allFaces: [simd_uint3] = []

        var vertexOffset: UInt32 = 0

        for mesh in meshes {
            allVertices.append(contentsOf: mesh.worldVertices)
            allNormals.append(contentsOf: mesh.normals)

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
