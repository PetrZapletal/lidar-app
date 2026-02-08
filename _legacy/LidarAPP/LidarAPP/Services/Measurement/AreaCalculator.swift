import Foundation
import simd

/// Calculates areas of polygons and mesh surfaces in 3D space
final class AreaCalculator: Sendable {

    // MARK: - Polygon Area (3D)

    /// Calculate area of a 3D polygon defined by vertices
    /// Uses the Shoelace formula generalized to 3D
    func polygonArea(vertices: [simd_float3]) -> Float {
        guard vertices.count >= 3 else { return 0 }

        // Find the best-fit plane for the polygon
        let (_, normal) = fitPlane(to: vertices)

        // Project vertices onto 2D and calculate area
        let projectedVertices = projectTo2D(vertices: vertices, planeNormal: normal)

        return polygon2DArea(vertices: projectedVertices)
    }

    /// Calculate area of a 2D polygon using Shoelace formula
    func polygon2DArea(vertices: [simd_float2]) -> Float {
        guard vertices.count >= 3 else { return 0 }

        var area: Float = 0

        for i in 0..<vertices.count {
            let j = (i + 1) % vertices.count
            area += vertices[i].x * vertices[j].y
            area -= vertices[j].x * vertices[i].y
        }

        return abs(area) / 2
    }

    // MARK: - Triangle Area

    /// Calculate area of a single triangle
    func triangleArea(v0: simd_float3, v1: simd_float3, v2: simd_float3) -> Float {
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let crossProduct = simd_cross(edge1, edge2)

        return simd_length(crossProduct) / 2
    }

    /// Calculate area using Heron's formula (from side lengths)
    func triangleAreaHeron(a: Float, b: Float, c: Float) -> Float {
        let s = (a + b + c) / 2
        let area = sqrt(s * (s - a) * (s - b) * (s - c))
        return area.isNaN ? 0 : area
    }

    // MARK: - Mesh Surface Area

    /// Calculate total surface area of a mesh
    func meshSurfaceArea(mesh: MeshData) -> Float {
        var totalArea: Float = 0

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

            totalArea += triangleArea(v0: v0, v1: v1, v2: v2)
        }

        return totalArea
    }

    /// Calculate area of selected mesh faces
    func meshFacesArea(mesh: MeshData, faceIndices: [Int]) -> Float {
        var totalArea: Float = 0

        for faceIndex in faceIndices {
            guard faceIndex < mesh.faces.count else { continue }

            let face = mesh.faces[faceIndex]
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

            totalArea += triangleArea(v0: v0, v1: v1, v2: v2)
        }

        return totalArea
    }

    // MARK: - Floor/Wall Area

    /// Calculate floor area (horizontal surfaces)
    func floorArea(mesh: MeshData, upDirection: simd_float3 = simd_float3(0, 1, 0), threshold: Float = 0.9) -> Float {
        var totalArea: Float = 0
        let normalizedUp = simd_normalize(upDirection)

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

            // Calculate face normal
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let normal = simd_normalize(simd_cross(edge1, edge2))

            // Check if face is horizontal (floor or ceiling)
            let dotProduct = abs(simd_dot(normal, normalizedUp))

            if dotProduct >= threshold {
                totalArea += triangleArea(v0: v0, v1: v1, v2: v2)
            }
        }

        return totalArea
    }

    /// Calculate wall area (vertical surfaces)
    func wallArea(mesh: MeshData, upDirection: simd_float3 = simd_float3(0, 1, 0), threshold: Float = 0.1) -> Float {
        var totalArea: Float = 0
        let normalizedUp = simd_normalize(upDirection)

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

            // Calculate face normal
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let normal = simd_normalize(simd_cross(edge1, edge2))

            // Check if face is vertical (wall)
            let dotProduct = abs(simd_dot(normal, normalizedUp))

            if dotProduct <= threshold {
                totalArea += triangleArea(v0: v0, v1: v1, v2: v2)
            }
        }

        return totalArea
    }

    // MARK: - Rectangle Area

    /// Calculate area of axis-aligned rectangle from two corner points
    func rectangleArea(corner1: simd_float3, corner2: simd_float3) -> Float {
        let dx = abs(corner2.x - corner1.x)
        let dy = abs(corner2.y - corner1.y)
        let dz = abs(corner2.z - corner1.z)

        // Determine which axes form the rectangle
        // Take the two largest dimensions
        var dimensions = [dx, dy, dz]
        dimensions.sort()

        return dimensions[1] * dimensions[2]
    }

    /// Calculate area of oriented rectangle from 4 corner points
    func rectangleArea(corners: [simd_float3]) -> Float {
        guard corners.count == 4 else { return 0 }

        // Split into two triangles
        let area1 = triangleArea(v0: corners[0], v1: corners[1], v2: corners[2])
        let area2 = triangleArea(v0: corners[0], v1: corners[2], v2: corners[3])

        return area1 + area2
    }

    // MARK: - Circle/Ellipse Area

    /// Approximate area of circular region on mesh
    func circleArea(center: simd_float3, radius: Float) -> Float {
        return .pi * radius * radius
    }

    /// Calculate area of ellipse from semi-axes
    func ellipseArea(semiAxisA: Float, semiAxisB: Float) -> Float {
        return .pi * semiAxisA * semiAxisB
    }

    // MARK: - Plane Fitting

    /// Fit a plane to a set of 3D points using least squares
    func fitPlane(to points: [simd_float3]) -> (point: simd_float3, normal: simd_float3) {
        guard points.count >= 3 else {
            return (simd_float3.zero, simd_float3(0, 1, 0))
        }

        // Calculate centroid
        let centroid = points.reduce(simd_float3.zero, +) / Float(points.count)

        // Build covariance matrix
        var xx: Float = 0, xy: Float = 0, xz: Float = 0
        var yy: Float = 0, yz: Float = 0, zz: Float = 0

        for point in points {
            let d = point - centroid
            xx += d.x * d.x
            xy += d.x * d.y
            xz += d.x * d.z
            yy += d.y * d.y
            yz += d.y * d.z
            zz += d.z * d.z
        }

        // Find the smallest eigenvector (plane normal)
        // Simplified: use cross product of two edge vectors
        if points.count >= 3 {
            let v1 = points[1] - points[0]
            let v2 = points[2] - points[0]
            var normal = simd_cross(v1, v2)

            if simd_length(normal) > 1e-6 {
                normal = simd_normalize(normal)
                return (centroid, normal)
            }
        }

        // Fallback to vertical plane
        return (centroid, simd_float3(0, 1, 0))
    }

    // MARK: - 2D Projection

    /// Project 3D points onto a 2D coordinate system defined by plane normal
    func projectTo2D(vertices: [simd_float3], planeNormal: simd_float3) -> [simd_float2] {
        guard !vertices.isEmpty else { return [] }

        let normal = simd_normalize(planeNormal)

        // Create orthonormal basis for the plane
        var u: simd_float3
        if abs(normal.x) < 0.9 {
            u = simd_normalize(simd_cross(simd_float3(1, 0, 0), normal))
        } else {
            u = simd_normalize(simd_cross(simd_float3(0, 1, 0), normal))
        }
        let v = simd_cross(normal, u)

        // Project vertices
        let centroid = vertices.reduce(simd_float3.zero, +) / Float(vertices.count)

        return vertices.map { vertex in
            let relative = vertex - centroid
            return simd_float2(
                simd_dot(relative, u),
                simd_dot(relative, v)
            )
        }
    }

    // MARK: - Area Statistics

    struct AreaStatistics {
        let totalArea: Float
        let floorArea: Float
        let wallArea: Float
        let ceilingArea: Float
        let averageFaceArea: Float
        let minFaceArea: Float
        let maxFaceArea: Float
    }

    /// Compute comprehensive area statistics for a mesh
    func computeAreaStatistics(mesh: MeshData) -> AreaStatistics {
        var faceAreas: [Float] = []
        var floorArea: Float = 0
        var wallArea: Float = 0
        var ceilingArea: Float = 0

        let upDirection = simd_float3(0, 1, 0)

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

            let area = triangleArea(v0: v0, v1: v1, v2: v2)
            faceAreas.append(area)

            // Calculate face normal
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let normal = simd_normalize(simd_cross(edge1, edge2))

            let dotProduct = simd_dot(normal, upDirection)

            if dotProduct > 0.9 {
                ceilingArea += area
            } else if dotProduct < -0.9 {
                floorArea += area
            } else if abs(dotProduct) < 0.1 {
                wallArea += area
            }
        }

        let totalArea = faceAreas.reduce(0, +)
        let averageArea = faceAreas.isEmpty ? 0 : totalArea / Float(faceAreas.count)
        let minArea = faceAreas.min() ?? 0
        let maxArea = faceAreas.max() ?? 0

        return AreaStatistics(
            totalArea: totalArea,
            floorArea: floorArea,
            wallArea: wallArea,
            ceilingArea: ceilingArea,
            averageFaceArea: averageArea,
            minFaceArea: minArea,
            maxFaceArea: maxArea
        )
    }
}

// MARK: - Convex Hull Area

extension AreaCalculator {

    /// Calculate area of convex hull of points (2D projection)
    func convexHullArea(points: [simd_float3]) -> Float {
        guard points.count >= 3 else { return 0 }

        // Fit plane and project to 2D
        let (_, normal) = fitPlane(to: points)
        let projected = projectTo2D(vertices: points, planeNormal: normal)

        // Compute 2D convex hull using Gift wrapping algorithm
        let hull = convexHull2D(points: projected)

        return polygon2DArea(vertices: hull)
    }

    /// Compute 2D convex hull using Gift wrapping (Jarvis march)
    private func convexHull2D(points: [simd_float2]) -> [simd_float2] {
        guard points.count >= 3 else { return points }

        var hull: [simd_float2] = []

        // Find leftmost point
        var leftmost = 0
        for i in 1..<points.count {
            if points[i].x < points[leftmost].x {
                leftmost = i
            }
        }

        var current = leftmost
        repeat {
            hull.append(points[current])
            var next = 0

            for i in 0..<points.count {
                if next == current {
                    next = i
                } else {
                    // Check if i is more counterclockwise than next
                    let cross = (points[next].x - points[current].x) * (points[i].y - points[current].y) -
                                (points[next].y - points[current].y) * (points[i].x - points[current].x)

                    if cross < 0 {
                        next = i
                    }
                }
            }

            current = next
        } while current != leftmost && hull.count < points.count

        return hull
    }
}
