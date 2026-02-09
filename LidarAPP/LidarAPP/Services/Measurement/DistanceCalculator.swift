import Foundation
import simd

/// Precise distance calculations with surface snapping and ray-mesh intersection.
/// Provides static utility methods for various distance computation scenarios.
struct DistanceCalculator {

    // MARK: - Basic Distance

    /// Euclidean distance between two points in 3D space
    static func distance(from: simd_float3, to: simd_float3) -> Float {
        simd_distance(from, to)
    }

    /// Squared distance (avoids sqrt, useful for comparisons)
    static func distanceSquared(from: simd_float3, to: simd_float3) -> Float {
        simd_distance_squared(from, to)
    }

    // MARK: - Surface Distance (Geodesic Approximation)

    /// Approximate geodesic distance along a mesh surface.
    /// Uses greedy edge-walking from the closest vertex to `from` towards the closest vertex to `to`.
    /// This is an approximation -- true geodesic computation requires Dijkstra over the mesh graph.
    static func surfaceDistance(from: simd_float3, to: simd_float3, mesh: MeshData) -> Float {
        guard !mesh.vertices.isEmpty, !mesh.faces.isEmpty else {
            return distance(from: from, to: to)
        }

        let worldVerts = mesh.worldVertices

        // Find nearest vertex indices
        let startIdx = closestVertexIndex(to: from, in: worldVerts)
        let endIdx = closestVertexIndex(to: to, in: worldVerts)

        guard startIdx != endIdx else {
            return 0
        }

        // Build adjacency list
        let adjacency = buildAdjacency(faces: mesh.faces, vertexCount: worldVerts.count)

        // Dijkstra's algorithm for shortest path along mesh edges
        let dist = dijkstra(
            adjacency: adjacency,
            vertices: worldVerts,
            source: startIdx,
            target: endIdx
        )

        // Add distance from query points to their closest vertices
        let startOffset = simd_distance(from, worldVerts[startIdx])
        let endOffset = simd_distance(to, worldVerts[endIdx])

        return dist + startOffset + endOffset
    }

    // MARK: - Surface Snapping

    /// Snap a point to the nearest surface position on the mesh.
    /// Checks each triangle and returns the closest surface point.
    static func snapToSurface(point: simd_float3, mesh: MeshData) -> simd_float3 {
        guard !mesh.vertices.isEmpty, !mesh.faces.isEmpty else {
            return point
        }

        let worldVerts = mesh.worldVertices
        var bestPoint = point
        var bestDistSq: Float = .greatestFiniteMagnitude

        for face in mesh.faces {
            let v0 = worldVerts[Int(face.x)]
            let v1 = worldVerts[Int(face.y)]
            let v2 = worldVerts[Int(face.z)]

            let candidate = closestPointOnTriangle(point: point, v0: v0, v1: v1, v2: v2)
            let dSq = simd_distance_squared(point, candidate)

            if dSq < bestDistSq {
                bestDistSq = dSq
                bestPoint = candidate
            }
        }

        return bestPoint
    }

    // MARK: - Ray-Mesh Intersection

    /// Find the intersection point of a ray with a mesh using the Moller-Trumbore algorithm.
    /// Returns the nearest intersection point, or nil if no intersection.
    static func rayMeshIntersection(
        rayOrigin: simd_float3,
        rayDirection: simd_float3,
        mesh: MeshData
    ) -> simd_float3? {
        guard !mesh.vertices.isEmpty, !mesh.faces.isEmpty else {
            return nil
        }

        let worldVerts = mesh.worldVertices
        let normalizedDir = simd_normalize(rayDirection)
        var nearestT: Float = .greatestFiniteMagnitude
        var hitPoint: simd_float3?

        for face in mesh.faces {
            let v0 = worldVerts[Int(face.x)]
            let v1 = worldVerts[Int(face.y)]
            let v2 = worldVerts[Int(face.z)]

            if let t = mollerTrumboreIntersection(
                rayOrigin: rayOrigin,
                rayDirection: normalizedDir,
                v0: v0,
                v1: v1,
                v2: v2
            ) {
                if t > 0 && t < nearestT {
                    nearestT = t
                    hitPoint = rayOrigin + normalizedDir * t
                }
            }
        }

        return hitPoint
    }

    // MARK: - Closest Point on Triangle

    /// Find the closest point on a triangle to a given point.
    /// Uses the projection method with Voronoi region checks.
    static func closestPointOnTriangle(
        point: simd_float3,
        v0: simd_float3,
        v1: simd_float3,
        v2: simd_float3
    ) -> simd_float3 {
        let ab = v1 - v0
        let ac = v2 - v0
        let ap = point - v0

        let d1 = simd_dot(ab, ap)
        let d2 = simd_dot(ac, ap)

        // Closest to v0
        if d1 <= 0 && d2 <= 0 {
            return v0
        }

        let bp = point - v1
        let d3 = simd_dot(ab, bp)
        let d4 = simd_dot(ac, bp)

        // Closest to v1
        if d3 >= 0 && d4 <= d3 {
            return v1
        }

        // Edge v0-v1
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 {
            let v = d1 / (d1 - d3)
            return v0 + ab * v
        }

        let cp = point - v2
        let d5 = simd_dot(ab, cp)
        let d6 = simd_dot(ac, cp)

        // Closest to v2
        if d6 >= 0 && d5 <= d6 {
            return v2
        }

        // Edge v0-v2
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 {
            let w = d2 / (d2 - d6)
            return v0 + ac * w
        }

        // Edge v1-v2
        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return v1 + (v2 - v1) * w
        }

        // Inside the triangle
        let denom = 1.0 / (va + vb + vc)
        let baryV = vb * denom
        let baryW = vc * denom
        return v0 + ab * baryV + ac * baryW
    }

    // MARK: - Private Helpers

    /// Moller-Trumbore ray-triangle intersection.
    /// Returns the parametric t value if intersection occurs, nil otherwise.
    private static func mollerTrumboreIntersection(
        rayOrigin: simd_float3,
        rayDirection: simd_float3,
        v0: simd_float3,
        v1: simd_float3,
        v2: simd_float3
    ) -> Float? {
        let epsilon: Float = 1e-8

        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let h = simd_cross(rayDirection, edge2)
        let a = simd_dot(edge1, h)

        // Ray is parallel to triangle
        if abs(a) < epsilon {
            return nil
        }

        let f = 1.0 / a
        let s = rayOrigin - v0
        let u = f * simd_dot(s, h)

        if u < 0.0 || u > 1.0 {
            return nil
        }

        let q = simd_cross(s, edge1)
        let v = f * simd_dot(rayDirection, q)

        if v < 0.0 || u + v > 1.0 {
            return nil
        }

        let t = f * simd_dot(edge2, q)
        return t
    }

    /// Find the index of the closest vertex to a query point
    private static func closestVertexIndex(to point: simd_float3, in vertices: [simd_float3]) -> Int {
        var bestIndex = 0
        var bestDistSq: Float = .greatestFiniteMagnitude

        for (index, vertex) in vertices.enumerated() {
            let dSq = simd_distance_squared(point, vertex)
            if dSq < bestDistSq {
                bestDistSq = dSq
                bestIndex = index
            }
        }

        return bestIndex
    }

    /// Build adjacency list from triangle faces
    private static func buildAdjacency(
        faces: [simd_uint3],
        vertexCount: Int
    ) -> [[Int]] {
        var adjacency = [[Int]](repeating: [], count: vertexCount)

        for face in faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            if !adjacency[i0].contains(i1) { adjacency[i0].append(i1) }
            if !adjacency[i0].contains(i2) { adjacency[i0].append(i2) }
            if !adjacency[i1].contains(i0) { adjacency[i1].append(i0) }
            if !adjacency[i1].contains(i2) { adjacency[i1].append(i2) }
            if !adjacency[i2].contains(i0) { adjacency[i2].append(i0) }
            if !adjacency[i2].contains(i1) { adjacency[i2].append(i1) }
        }

        return adjacency
    }

    /// Dijkstra's shortest path on mesh graph.
    /// Returns the shortest edge-distance from source to target vertex.
    private static func dijkstra(
        adjacency: [[Int]],
        vertices: [simd_float3],
        source: Int,
        target: Int
    ) -> Float {
        let count = vertices.count
        var dist = [Float](repeating: .greatestFiniteMagnitude, count: count)
        var visited = [Bool](repeating: false, count: count)
        dist[source] = 0

        // Simple priority queue using array (sufficient for typical mesh sizes)
        // For production with very large meshes, consider a proper min-heap.
        var queue: [(index: Int, distance: Float)] = [(source, 0)]

        while !queue.isEmpty {
            // Find minimum
            queue.sort { $0.distance < $1.distance }
            let current = queue.removeFirst()

            if current.index == target {
                return current.distance
            }

            if visited[current.index] {
                continue
            }
            visited[current.index] = true

            for neighbor in adjacency[current.index] {
                if visited[neighbor] { continue }

                let edgeLen = simd_distance(vertices[current.index], vertices[neighbor])
                let newDist = dist[current.index] + edgeLen

                if newDist < dist[neighbor] {
                    dist[neighbor] = newDist
                    queue.append((neighbor, newDist))
                }
            }
        }

        return dist[target]
    }
}
