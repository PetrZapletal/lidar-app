import Foundation
import simd
import Accelerate

/// On-device mesh correction using geometric algorithms.
///
/// Provides a suite of mesh refinement operations including normal smoothing,
/// degenerate face removal, Laplacian smoothing, and small hole filling.
/// All operations use efficient in-memory processing suitable for real-time
/// or near-real-time use on device.
@MainActor
@Observable
final class MeshCorrectionModel {

    // MARK: - Configuration

    struct Configuration {
        var laplacianFactor: Float = 0.5
        var laplacianIterations: Int = 2
        var normalSmoothIterations: Int = 3
        var maxHoleEdges: Int = 10
        var degenerateAreaThreshold: Float = 1e-10
    }

    // MARK: - Properties

    private(set) var configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Normal Smoothing

    /// Smooth mesh normals by averaging normals of vertices sharing faces.
    ///
    /// Iteratively averages the normals of each vertex with the normals of
    /// its neighbors (vertices connected via shared faces). This produces
    /// a smoother visual appearance without changing geometry.
    ///
    /// - Parameters:
    ///   - meshData: The input mesh to smooth normals for.
    ///   - iterations: Number of smoothing iterations to apply.
    /// - Returns: A new MeshData with smoothed normals.
    func smoothNormals(meshData: MeshData, iterations: Int? = nil) -> MeshData {
        let iterCount = iterations ?? configuration.normalSmoothIterations
        guard !meshData.normals.isEmpty, !meshData.faces.isEmpty else {
            debugLog("Skipping normal smoothing: empty normals or faces", category: .logCategoryProcessing)
            return meshData
        }

        debugLog("Smoothing normals: \(meshData.vertexCount) vertices, \(iterCount) iterations", category: .logCategoryProcessing)

        // Build adjacency list: for each vertex, collect indices of neighboring vertices
        let adjacency = buildAdjacencyList(faces: meshData.faces, vertexCount: meshData.vertexCount)

        var currentNormals = meshData.normals

        for iter in 0..<iterCount {
            var smoothedNormals = [simd_float3](repeating: .zero, count: meshData.vertexCount)

            for vertexIndex in 0..<meshData.vertexCount {
                let neighbors = adjacency[vertexIndex]

                if neighbors.isEmpty {
                    smoothedNormals[vertexIndex] = currentNormals[vertexIndex]
                    continue
                }

                // Accumulate neighbor normals
                var accumulated = currentNormals[vertexIndex]
                for neighborIndex in neighbors {
                    accumulated += currentNormals[neighborIndex]
                }

                // Average and normalize
                let averaged = accumulated / Float(neighbors.count + 1)
                let len = simd_length(averaged)
                smoothedNormals[vertexIndex] = len > .ulpOfOne ? simd_normalize(averaged) : currentNormals[vertexIndex]
            }

            currentNormals = smoothedNormals
            debugLog("Normal smoothing iteration \(iter + 1)/\(iterCount) completed", category: .logCategoryProcessing)
        }

        return MeshData(
            id: meshData.id,
            anchorIdentifier: meshData.anchorIdentifier,
            vertices: meshData.vertices,
            normals: currentNormals,
            faces: meshData.faces,
            textureCoordinates: meshData.textureCoordinates,
            classifications: meshData.classifications,
            transform: meshData.transform
        )
    }

    // MARK: - Degenerate Face Removal

    /// Remove degenerate triangles from the mesh.
    ///
    /// Removes triangles that have zero or near-zero area (collapsed triangles)
    /// and triangles with duplicate vertex indices. This prevents rendering
    /// artifacts and improves downstream processing.
    ///
    /// - Parameter meshData: The input mesh to clean.
    /// - Returns: A new MeshData with degenerate faces removed.
    func removeDegenerateFaces(meshData: MeshData) -> MeshData {
        guard !meshData.faces.isEmpty else {
            debugLog("Skipping degenerate removal: no faces", category: .logCategoryProcessing)
            return meshData
        }

        let originalCount = meshData.faceCount
        var validFaces: [simd_uint3] = []
        validFaces.reserveCapacity(meshData.faces.count)

        for face in meshData.faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            // Skip faces with duplicate vertex indices
            if i0 == i1 || i1 == i2 || i0 == i2 {
                continue
            }

            // Skip faces referencing out-of-bounds vertices
            guard i0 < meshData.vertexCount,
                  i1 < meshData.vertexCount,
                  i2 < meshData.vertexCount else {
                continue
            }

            // Compute triangle area via cross product
            let v0 = meshData.vertices[i0]
            let v1 = meshData.vertices[i1]
            let v2 = meshData.vertices[i2]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let cross = simd_cross(edge1, edge2)
            let area = simd_length(cross) * 0.5

            // Skip triangles with negligible area
            if area < configuration.degenerateAreaThreshold {
                continue
            }

            validFaces.append(face)
        }

        let removedCount = originalCount - validFaces.count
        if removedCount > 0 {
            infoLog("Removed \(removedCount) degenerate faces (kept \(validFaces.count)/\(originalCount))", category: .logCategoryProcessing)
        } else {
            debugLog("No degenerate faces found", category: .logCategoryProcessing)
        }

        return MeshData(
            id: meshData.id,
            anchorIdentifier: meshData.anchorIdentifier,
            vertices: meshData.vertices,
            normals: meshData.normals,
            faces: validFaces,
            textureCoordinates: meshData.textureCoordinates,
            classifications: meshData.classifications,
            transform: meshData.transform
        )
    }

    // MARK: - Laplacian Smoothing

    /// Apply Laplacian smoothing to vertex positions.
    ///
    /// Each vertex is moved towards the centroid of its neighbors by a
    /// configurable factor. This reduces noise and produces a smoother
    /// surface while preserving overall shape.
    ///
    /// - Parameters:
    ///   - meshData: The input mesh to smooth.
    ///   - factor: Blending factor [0, 1] where 0 means no smoothing and 1
    ///     means full smoothing toward neighbor centroid.
    ///   - iterations: Number of smoothing iterations.
    /// - Returns: A new MeshData with smoothed vertex positions.
    func laplacianSmooth(meshData: MeshData, factor: Float? = nil, iterations: Int? = nil) -> MeshData {
        let smoothFactor = factor ?? configuration.laplacianFactor
        let iterCount = iterations ?? configuration.laplacianIterations

        guard !meshData.vertices.isEmpty, !meshData.faces.isEmpty else {
            debugLog("Skipping Laplacian smoothing: empty mesh", category: .logCategoryProcessing)
            return meshData
        }

        debugLog(
            "Laplacian smoothing: \(meshData.vertexCount) vertices, factor=\(smoothFactor), iterations=\(iterCount)",
            category: .logCategoryProcessing
        )

        let adjacency = buildAdjacencyList(faces: meshData.faces, vertexCount: meshData.vertexCount)

        // Identify boundary vertices (connected to boundary edges)
        let boundaryVertices = findBoundaryVertices(faces: meshData.faces, vertexCount: meshData.vertexCount)

        var currentVertices = meshData.vertices

        for iter in 0..<iterCount {
            var smoothedVertices = [simd_float3](repeating: .zero, count: meshData.vertexCount)

            for vertexIndex in 0..<meshData.vertexCount {
                let neighbors = adjacency[vertexIndex]

                // Do not smooth boundary vertices to preserve mesh edges
                if neighbors.isEmpty || boundaryVertices.contains(vertexIndex) {
                    smoothedVertices[vertexIndex] = currentVertices[vertexIndex]
                    continue
                }

                // Compute centroid of neighbors
                var centroid = simd_float3.zero
                for neighborIndex in neighbors {
                    centroid += currentVertices[neighborIndex]
                }
                centroid /= Float(neighbors.count)

                // Blend between original position and centroid
                smoothedVertices[vertexIndex] = simd_mix(
                    currentVertices[vertexIndex],
                    centroid,
                    simd_float3(repeating: smoothFactor)
                )
            }

            currentVertices = smoothedVertices
            debugLog("Laplacian smoothing iteration \(iter + 1)/\(iterCount) completed", category: .logCategoryProcessing)
        }

        // Recompute normals after vertex positions changed
        let recomputedNormals = recomputeNormals(
            vertices: currentVertices,
            faces: meshData.faces
        )

        return MeshData(
            id: meshData.id,
            anchorIdentifier: meshData.anchorIdentifier,
            vertices: currentVertices,
            normals: recomputedNormals,
            faces: meshData.faces,
            textureCoordinates: meshData.textureCoordinates,
            classifications: meshData.classifications,
            transform: meshData.transform
        )
    }

    // MARK: - Hole Filling

    /// Fill small holes in the mesh by detecting boundary loops and triangulating them.
    ///
    /// Identifies boundary edges (edges belonging to only one triangle), groups
    /// them into loops, and fills loops smaller than `maxHoleEdges` with a fan
    /// triangulation from the loop centroid.
    ///
    /// - Parameters:
    ///   - meshData: The input mesh with potential holes.
    ///   - maxHoleEdges: Maximum number of edges a hole can have to be filled.
    /// - Returns: A new MeshData with small holes filled.
    func fillSmallHoles(meshData: MeshData, maxHoleEdges: Int? = nil) -> MeshData {
        let maxEdges = maxHoleEdges ?? configuration.maxHoleEdges

        guard !meshData.faces.isEmpty else {
            debugLog("Skipping hole filling: no faces", category: .logCategoryProcessing)
            return meshData
        }

        debugLog("Finding holes in mesh with \(meshData.faceCount) faces", category: .logCategoryProcessing)

        // Find boundary edges: edges that belong to exactly one face
        var edgeFaceCount: [EdgeKey: Int] = [:]
        var boundaryEdges: [EdgeKey] = []

        for face in meshData.faces {
            let edges: [EdgeKey] = [
                EdgeKey(Int(face.x), Int(face.y)),
                EdgeKey(Int(face.y), Int(face.z)),
                EdgeKey(Int(face.z), Int(face.x))
            ]
            for edge in edges {
                edgeFaceCount[edge, default: 0] += 1
            }
        }

        for (edge, count) in edgeFaceCount where count == 1 {
            boundaryEdges.append(edge)
        }

        if boundaryEdges.isEmpty {
            debugLog("No boundary edges found - mesh is watertight", category: .logCategoryProcessing)
            return meshData
        }

        debugLog("Found \(boundaryEdges.count) boundary edges", category: .logCategoryProcessing)

        // Group boundary edges into loops
        let loops = findBoundaryLoops(edges: boundaryEdges)

        var newVertices = meshData.vertices
        var newNormals = meshData.normals
        var newFaces = meshData.faces
        var filledHoles = 0

        for loop in loops {
            guard loop.count >= 3, loop.count <= maxEdges else {
                continue
            }

            // Compute centroid of the hole boundary
            var centroid = simd_float3.zero
            var centroidNormal = simd_float3.zero

            for vertexIndex in loop {
                centroid += meshData.vertices[vertexIndex]
                if vertexIndex < meshData.normals.count {
                    centroidNormal += meshData.normals[vertexIndex]
                }
            }
            centroid /= Float(loop.count)

            let normalLen = simd_length(centroidNormal)
            centroidNormal = normalLen > .ulpOfOne ? simd_normalize(centroidNormal) : simd_float3(0, 1, 0)

            // Add centroid vertex
            let centroidIndex = UInt32(newVertices.count)
            newVertices.append(centroid)
            newNormals.append(centroidNormal)

            // Create fan triangulation from centroid to boundary loop
            for i in 0..<loop.count {
                let nextI = (i + 1) % loop.count
                newFaces.append(simd_uint3(
                    UInt32(loop[i]),
                    UInt32(loop[nextI]),
                    centroidIndex
                ))
            }

            filledHoles += 1
        }

        if filledHoles > 0 {
            infoLog("Filled \(filledHoles) holes (added \(newFaces.count - meshData.faceCount) faces)", category: .logCategoryProcessing)
        } else {
            debugLog("No holes small enough to fill (max \(maxEdges) edges)", category: .logCategoryProcessing)
        }

        return MeshData(
            id: meshData.id,
            anchorIdentifier: meshData.anchorIdentifier,
            vertices: newVertices,
            normals: newNormals,
            faces: newFaces,
            textureCoordinates: meshData.textureCoordinates,
            classifications: meshData.classifications,
            transform: meshData.transform
        )
    }

    // MARK: - Full Correction Pipeline

    /// Run the full mesh correction pipeline.
    ///
    /// Applies corrections in order: degenerate face removal, Laplacian vertex
    /// smoothing, then normal smoothing. Each stage produces a progressively
    /// cleaner mesh.
    ///
    /// - Parameter meshData: The input mesh to correct.
    /// - Returns: A fully corrected MeshData.
    func correctMesh(meshData: MeshData) -> MeshData {
        debugLog("Starting mesh correction pipeline", category: .logCategoryProcessing)

        // Stage 1: Remove degenerate faces
        let cleaned = removeDegenerateFaces(meshData: meshData)

        // Stage 2: Laplacian smoothing of vertex positions
        let smoothed = laplacianSmooth(meshData: cleaned)

        // Stage 3: Normal smoothing for visual quality
        let result = smoothNormals(meshData: smoothed)

        infoLog(
            "Mesh correction complete: \(meshData.faceCount) -> \(result.faceCount) faces, \(meshData.vertexCount) -> \(result.vertexCount) vertices",
            category: .logCategoryProcessing
        )

        return result
    }

    // MARK: - Private Helpers

    /// Build an adjacency list mapping each vertex index to its connected neighbors.
    private func buildAdjacencyList(faces: [simd_uint3], vertexCount: Int) -> [Set<Int>] {
        var adjacency = [Set<Int>](repeating: [], count: vertexCount)

        for face in faces {
            let a = Int(face.x)
            let b = Int(face.y)
            let c = Int(face.z)

            guard a < vertexCount, b < vertexCount, c < vertexCount else { continue }

            adjacency[a].insert(b)
            adjacency[a].insert(c)
            adjacency[b].insert(a)
            adjacency[b].insert(c)
            adjacency[c].insert(a)
            adjacency[c].insert(b)
        }

        return adjacency
    }

    /// Identify boundary vertices: vertices connected to boundary edges
    /// (edges shared by exactly one face).
    private func findBoundaryVertices(faces: [simd_uint3], vertexCount: Int) -> Set<Int> {
        var edgeFaceCount: [EdgeKey: Int] = [:]

        for face in faces {
            let edges: [EdgeKey] = [
                EdgeKey(Int(face.x), Int(face.y)),
                EdgeKey(Int(face.y), Int(face.z)),
                EdgeKey(Int(face.z), Int(face.x))
            ]
            for edge in edges {
                edgeFaceCount[edge, default: 0] += 1
            }
        }

        var boundary = Set<Int>()
        for (edge, count) in edgeFaceCount where count == 1 {
            boundary.insert(edge.v0)
            boundary.insert(edge.v1)
        }

        return boundary
    }

    /// Recompute vertex normals from face normals using area-weighted averaging.
    private func recomputeNormals(vertices: [simd_float3], faces: [simd_uint3]) -> [simd_float3] {
        var normals = [simd_float3](repeating: .zero, count: vertices.count)

        for face in faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }

            let v0 = vertices[i0]
            let v1 = vertices[i1]
            let v2 = vertices[i2]

            // Cross product gives area-weighted normal
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let faceNormal = simd_cross(edge1, edge2)

            normals[i0] += faceNormal
            normals[i1] += faceNormal
            normals[i2] += faceNormal
        }

        // Normalize all vertex normals
        for i in 0..<normals.count {
            let len = simd_length(normals[i])
            if len > .ulpOfOne {
                normals[i] = simd_normalize(normals[i])
            }
        }

        return normals
    }

    /// Group boundary edges into connected loops.
    private func findBoundaryLoops(edges: [EdgeKey]) -> [[Int]] {
        guard !edges.isEmpty else { return [] }

        // Build adjacency from boundary edges
        var adjacency: [Int: [Int]] = [:]
        for edge in edges {
            adjacency[edge.v0, default: []].append(edge.v1)
            adjacency[edge.v1, default: []].append(edge.v0)
        }

        var visited = Set<Int>()
        var loops: [[Int]] = []

        for startVertex in adjacency.keys {
            guard !visited.contains(startVertex) else { continue }

            var loop: [Int] = []
            var current = startVertex

            // Walk the boundary
            while !visited.contains(current) {
                visited.insert(current)
                loop.append(current)

                guard let neighbors = adjacency[current] else { break }

                // Find the next unvisited neighbor
                var foundNext = false
                for neighbor in neighbors where !visited.contains(neighbor) {
                    current = neighbor
                    foundNext = true
                    break
                }

                if !foundNext {
                    break
                }
            }

            if loop.count >= 3 {
                loops.append(loop)
            }
        }

        return loops
    }
}

// MARK: - Edge Key

/// Hashable edge key for undirected edges, where EdgeKey(a, b) == EdgeKey(b, a).
private struct EdgeKey: Hashable {
    let v0: Int
    let v1: Int

    init(_ a: Int, _ b: Int) {
        // Canonical ordering ensures EdgeKey(a,b) == EdgeKey(b,a)
        if a <= b {
            v0 = a
            v1 = b
        } else {
            v0 = b
            v1 = a
        }
    }
}
