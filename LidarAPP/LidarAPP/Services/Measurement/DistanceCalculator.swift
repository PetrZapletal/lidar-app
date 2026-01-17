import Foundation
import simd

/// Calculates distances between points and surfaces in 3D space
final class DistanceCalculator: Sendable {

    // MARK: - Point-to-Point Distance

    /// Calculate Euclidean distance between two points
    func pointToPointDistance(from p1: simd_float3, to p2: simd_float3) -> Float {
        simd_distance(p1, p2)
    }

    /// Calculate squared distance (faster, useful for comparisons)
    func pointToPointDistanceSquared(from p1: simd_float3, to p2: simd_float3) -> Float {
        simd_distance_squared(p1, p2)
    }

    /// Calculate Manhattan distance (L1 norm)
    func manhattanDistance(from p1: simd_float3, to p2: simd_float3) -> Float {
        abs(p1.x - p2.x) + abs(p1.y - p2.y) + abs(p1.z - p2.z)
    }

    // MARK: - Polyline Distance

    /// Calculate total length of a polyline
    func polylineDistance(points: [simd_float3]) -> Float {
        guard points.count >= 2 else { return 0 }

        var totalDistance: Float = 0
        for i in 0..<(points.count - 1) {
            totalDistance += pointToPointDistance(from: points[i], to: points[i + 1])
        }

        return totalDistance
    }

    /// Calculate segment lengths of a polyline
    func polylineSegments(points: [simd_float3]) -> [Float] {
        guard points.count >= 2 else { return [] }

        var segments: [Float] = []
        for i in 0..<(points.count - 1) {
            segments.append(pointToPointDistance(from: points[i], to: points[i + 1]))
        }

        return segments
    }

    // MARK: - Point-to-Line Distance

    /// Calculate perpendicular distance from point to line segment
    func pointToLineSegmentDistance(
        point: simd_float3,
        lineStart: simd_float3,
        lineEnd: simd_float3
    ) -> Float {
        let lineDir = lineEnd - lineStart
        let lineLength = simd_length(lineDir)

        guard lineLength > 0 else {
            return pointToPointDistance(from: point, to: lineStart)
        }

        let normalizedDir = lineDir / lineLength
        let pointVector = point - lineStart

        // Project point onto line
        let projection = simd_dot(pointVector, normalizedDir)

        if projection <= 0 {
            // Closest to line start
            return pointToPointDistance(from: point, to: lineStart)
        } else if projection >= lineLength {
            // Closest to line end
            return pointToPointDistance(from: point, to: lineEnd)
        } else {
            // Closest to somewhere on the line
            let closestPoint = lineStart + normalizedDir * projection
            return pointToPointDistance(from: point, to: closestPoint)
        }
    }

    /// Calculate distance from point to infinite line
    func pointToInfiniteLineDistance(
        point: simd_float3,
        linePoint: simd_float3,
        lineDirection: simd_float3
    ) -> Float {
        let normalizedDir = simd_normalize(lineDirection)
        let pointVector = point - linePoint

        let projection = simd_dot(pointVector, normalizedDir)
        let closestPoint = linePoint + normalizedDir * projection

        return pointToPointDistance(from: point, to: closestPoint)
    }

    // MARK: - Point-to-Plane Distance

    /// Calculate signed distance from point to plane
    func pointToPlaneDistance(
        point: simd_float3,
        planePoint: simd_float3,
        planeNormal: simd_float3
    ) -> Float {
        let normalizedNormal = simd_normalize(planeNormal)
        return simd_dot(point - planePoint, normalizedNormal)
    }

    /// Calculate absolute distance from point to plane
    func pointToPlaneDistanceAbsolute(
        point: simd_float3,
        planePoint: simd_float3,
        planeNormal: simd_float3
    ) -> Float {
        abs(pointToPlaneDistance(point: point, planePoint: planePoint, planeNormal: planeNormal))
    }

    // MARK: - Point-to-Triangle Distance

    /// Calculate distance from point to triangle
    func pointToTriangleDistance(
        point: simd_float3,
        v0: simd_float3,
        v1: simd_float3,
        v2: simd_float3
    ) -> Float {
        // Find closest point on triangle
        let closestPoint = closestPointOnTriangle(point: point, v0: v0, v1: v1, v2: v2)
        return pointToPointDistance(from: point, to: closestPoint)
    }

    /// Find closest point on triangle to given point
    func closestPointOnTriangle(
        point: simd_float3,
        v0: simd_float3,
        v1: simd_float3,
        v2: simd_float3
    ) -> simd_float3 {
        let edge0 = v1 - v0
        let edge1 = v2 - v0
        let v0ToPoint = v0 - point

        let a = simd_dot(edge0, edge0)
        let b = simd_dot(edge0, edge1)
        let c = simd_dot(edge1, edge1)
        let d = simd_dot(edge0, v0ToPoint)
        let e = simd_dot(edge1, v0ToPoint)

        let det = a * c - b * b
        var s = b * e - c * d
        var t = b * d - a * e

        if s + t <= det {
            if s < 0 {
                if t < 0 {
                    // Region 4
                    if d < 0 {
                        t = 0
                        s = min(max(-d / a, 0), 1)
                    } else {
                        s = 0
                        t = min(max(-e / c, 0), 1)
                    }
                } else {
                    // Region 3
                    s = 0
                    t = min(max(-e / c, 0), 1)
                }
            } else if t < 0 {
                // Region 5
                t = 0
                s = min(max(-d / a, 0), 1)
            } else {
                // Region 0 (inside triangle)
                let invDet: Float = 1.0 / det
                s *= invDet
                t *= invDet
            }
        } else {
            if s < 0 {
                // Region 2
                let tmp0 = b + d
                let tmp1 = c + e
                if tmp1 > tmp0 {
                    let numer = tmp1 - tmp0
                    let denom = a - 2 * b + c
                    s = min(max(numer / denom, 0), 1)
                    t = 1 - s
                } else {
                    s = 0
                    t = min(max(-e / c, 0), 1)
                }
            } else if t < 0 {
                // Region 6
                let tmp0 = b + e
                let tmp1 = a + d
                if tmp1 > tmp0 {
                    let numer = tmp1 - tmp0
                    let denom = a - 2 * b + c
                    t = min(max(numer / denom, 0), 1)
                    s = 1 - t
                } else {
                    t = 0
                    s = min(max(-d / a, 0), 1)
                }
            } else {
                // Region 1
                let numer = c + e - b - d
                if numer <= 0 {
                    s = 0
                } else {
                    let denom = a - 2 * b + c
                    s = min(max(numer / denom, 0), 1)
                }
                t = 1 - s
            }
        }

        return v0 + edge0 * s + edge1 * t
    }

    // MARK: - Angle Calculations

    /// Calculate angle at vertex between two vectors (in radians)
    func angleBetweenVectors(
        vertex: simd_float3,
        point1: simd_float3,
        point2: simd_float3
    ) -> Float {
        let v1 = simd_normalize(point1 - vertex)
        let v2 = simd_normalize(point2 - vertex)

        let dot = simd_clamp(simd_dot(v1, v2), -1, 1)
        return acos(dot)
    }

    /// Calculate angle between two direction vectors (in radians)
    func angleBetweenDirections(_ d1: simd_float3, _ d2: simd_float3) -> Float {
        let v1 = simd_normalize(d1)
        let v2 = simd_normalize(d2)

        let dot = simd_clamp(simd_dot(v1, v2), -1, 1)
        return acos(dot)
    }

    // MARK: - Ray-Mesh Intersection

    /// Find intersection point of ray with mesh
    func rayMeshIntersection(
        origin: simd_float3,
        direction: simd_float3,
        mesh: MeshData
    ) -> simd_float3? {
        let normalizedDir = simd_normalize(direction)
        var closestDistance: Float = .greatestFiniteMagnitude
        var closestPoint: simd_float3?

        // Check intersection with each triangle
        for face in mesh.faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            guard i0 < mesh.vertices.count &&
                  i1 < mesh.vertices.count &&
                  i2 < mesh.vertices.count else {
                continue
            }

            // Transform vertices to world space
            let v0 = mesh.worldVertices[i0]
            let v1 = mesh.worldVertices[i1]
            let v2 = mesh.worldVertices[i2]

            if let intersection = rayTriangleIntersection(
                origin: origin,
                direction: normalizedDir,
                v0: v0, v1: v1, v2: v2
            ) {
                let distance = simd_distance(origin, intersection)
                if distance < closestDistance {
                    closestDistance = distance
                    closestPoint = intersection
                }
            }
        }

        return closestPoint
    }

    /// Möller–Trumbore ray-triangle intersection
    func rayTriangleIntersection(
        origin: simd_float3,
        direction: simd_float3,
        v0: simd_float3,
        v1: simd_float3,
        v2: simd_float3
    ) -> simd_float3? {
        let epsilon: Float = 1e-6

        let edge1 = v1 - v0
        let edge2 = v2 - v0

        let h = simd_cross(direction, edge2)
        let a = simd_dot(edge1, h)

        // Ray is parallel to triangle
        if abs(a) < epsilon {
            return nil
        }

        let f = 1.0 / a
        let s = origin - v0
        let u = f * simd_dot(s, h)

        if u < 0 || u > 1 {
            return nil
        }

        let q = simd_cross(s, edge1)
        let v = f * simd_dot(direction, q)

        if v < 0 || u + v > 1 {
            return nil
        }

        let t = f * simd_dot(edge2, q)

        if t > epsilon {
            return origin + direction * t
        }

        return nil
    }

    // MARK: - Distance to Mesh

    /// Find closest point on mesh to given point
    func closestPointOnMesh(
        point: simd_float3,
        mesh: MeshData
    ) -> (point: simd_float3, distance: Float, faceIndex: Int)? {
        var closestDistance: Float = .greatestFiniteMagnitude
        var closestPoint: simd_float3?
        var closestFaceIndex: Int = -1

        for (faceIndex, face) in mesh.faces.enumerated() {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            guard i0 < mesh.vertices.count &&
                  i1 < mesh.vertices.count &&
                  i2 < mesh.vertices.count else {
                continue
            }

            let v0 = mesh.worldVertices[i0]
            let v1 = mesh.worldVertices[i1]
            let v2 = mesh.worldVertices[i2]

            let triangleClosest = closestPointOnTriangle(point: point, v0: v0, v1: v1, v2: v2)
            let distance = simd_distance(point, triangleClosest)

            if distance < closestDistance {
                closestDistance = distance
                closestPoint = triangleClosest
                closestFaceIndex = faceIndex
            }
        }

        if let closest = closestPoint, closestFaceIndex >= 0 {
            return (closest, closestDistance, closestFaceIndex)
        }

        return nil
    }

    // MARK: - Precision Helpers

    /// Snap point to nearest mesh vertex within threshold
    func snapToVertex(
        point: simd_float3,
        mesh: MeshData,
        threshold: Float = 0.02  // 2cm
    ) -> simd_float3 {
        var closestVertex = point
        var closestDistance = threshold

        for vertex in mesh.worldVertices {
            let distance = simd_distance(point, vertex)
            if distance < closestDistance {
                closestDistance = distance
                closestVertex = vertex
            }
        }

        return closestVertex
    }

    /// Snap point to nearest edge within threshold
    func snapToEdge(
        point: simd_float3,
        mesh: MeshData,
        threshold: Float = 0.02
    ) -> simd_float3 {
        var closestPoint = point
        var closestDistance = threshold

        for face in mesh.faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            guard i0 < mesh.vertices.count &&
                  i1 < mesh.vertices.count &&
                  i2 < mesh.vertices.count else {
                continue
            }

            let v0 = mesh.worldVertices[i0]
            let v1 = mesh.worldVertices[i1]
            let v2 = mesh.worldVertices[i2]

            // Check all three edges
            let edges = [(v0, v1), (v1, v2), (v2, v0)]

            for (start, end) in edges {
                let distance = pointToLineSegmentDistance(point: point, lineStart: start, lineEnd: end)
                if distance < closestDistance {
                    // Find closest point on edge
                    let edgeDir = end - start
                    let edgeLength = simd_length(edgeDir)
                    let normalizedDir = edgeDir / edgeLength
                    let projection = simd_dot(point - start, normalizedDir)
                    let clampedProjection = min(max(projection, 0), edgeLength)

                    closestPoint = start + normalizedDir * clampedProjection
                    closestDistance = distance
                }
            }
        }

        return closestPoint
    }
}
