import Foundation
import simd
import Accelerate

/// Area calculations for polygons and mesh surfaces.
/// Supports 3D polygon area via Newell's method, triangle area,
/// and projected area calculations (floor/wall).
struct AreaCalculator {

    // MARK: - Polygon Area (3D)

    /// Calculate the area of a 3D polygon using Newell's method.
    /// First computes the polygon normal via Newell's method,
    /// then uses the magnitude of the cross-product sum for the area.
    /// Works for both convex and simple (non-self-intersecting) polygons.
    static func polygonArea(points: [simd_float3]) -> Float {
        guard points.count >= 3 else { return 0 }

        // Newell's method: compute the polygon normal as
        //   N = sum over edges of cross(v_i, v_{i+1})
        // The magnitude of N equals twice the polygon area.
        var normalSum = simd_float3.zero

        for i in 0..<points.count {
            let current = points[i]
            let next = points[(i + 1) % points.count]

            // Accumulate cross product components (Newell's method)
            normalSum.x += (current.y - next.y) * (current.z + next.z)
            normalSum.y += (current.z - next.z) * (current.x + next.x)
            normalSum.z += (current.x - next.x) * (current.y + next.y)
        }

        return simd_length(normalSum) / 2.0
    }

    // MARK: - Mesh Surface Area

    /// Calculate the total surface area of a mesh, optionally filtering by face indices.
    /// If selectedFaces is nil, all faces are included.
    static func meshSurfaceArea(meshData: MeshData, selectedFaces: [Int]? = nil) -> Float {
        let worldVerts = meshData.worldVertices

        guard !worldVerts.isEmpty else { return 0 }

        if let selected = selectedFaces {
            return selected.reduce(Float(0)) { total, faceIndex in
                guard faceIndex >= 0, faceIndex < meshData.faces.count else { return total }
                let face = meshData.faces[faceIndex]
                return total + triangleArea(
                    v0: worldVerts[Int(face.x)],
                    v1: worldVerts[Int(face.y)],
                    v2: worldVerts[Int(face.z)]
                )
            }
        } else {
            return meshData.faces.reduce(Float(0)) { total, face in
                total + triangleArea(
                    v0: worldVerts[Int(face.x)],
                    v1: worldVerts[Int(face.y)],
                    v2: worldVerts[Int(face.z)]
                )
            }
        }
    }

    // MARK: - Triangle Area

    /// Area of a single triangle defined by three vertices.
    /// Uses the cross product magnitude formula: area = |cross(v1-v0, v2-v0)| / 2.
    static func triangleArea(v0: simd_float3, v1: simd_float3, v2: simd_float3) -> Float {
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let crossProduct = simd_cross(edge1, edge2)
        return simd_length(crossProduct) / 2.0
    }

    // MARK: - Projected Area Calculations

    /// Floor area: project polygon points to the XZ plane (Y = 0) and compute 2D area.
    /// Useful for room floor area estimation.
    static func floorArea(points: [simd_float3]) -> Float {
        guard points.count >= 3 else { return 0 }

        // Project to XZ plane
        let projected = points.map { simd_float3($0.x, 0, $0.z) }
        return shoelaceArea2D(projected, axis1: \.x, axis2: \.z)
    }

    /// Wall area: project polygon points to the best-fit vertical plane and compute 2D area.
    /// Determines the dominant horizontal axis from the polygon normal.
    static func wallArea(points: [simd_float3]) -> Float {
        guard points.count >= 3 else { return 0 }

        // Compute polygon normal to determine the best projection
        var normal = simd_float3.zero
        for i in 0..<points.count {
            let current = points[i]
            let next = points[(i + 1) % points.count]

            normal.x += (current.y - next.y) * (current.z + next.z)
            normal.y += (current.z - next.z) * (current.x + next.x)
            normal.z += (current.x - next.x) * (current.y + next.y)
        }

        // Determine which axis to drop based on the largest normal component
        let absNormal = simd_abs(normal)

        if absNormal.x >= absNormal.y && absNormal.x >= absNormal.z {
            // Normal is primarily along X; project to YZ plane
            return shoelaceArea2D(points, axis1: \.y, axis2: \.z)
        } else if absNormal.z >= absNormal.x && absNormal.z >= absNormal.y {
            // Normal is primarily along Z; project to XY plane
            return shoelaceArea2D(points, axis1: \.x, axis2: \.y)
        } else {
            // Normal is primarily along Y; project to XZ plane (floor-like)
            return shoelaceArea2D(points, axis1: \.x, axis2: \.z)
        }
    }

    // MARK: - Batch Triangle Area (Accelerate)

    /// Calculate areas for multiple triangles using Accelerate for batch operations.
    /// Returns an array of areas corresponding to each face.
    static func batchTriangleAreas(vertices: [simd_float3], faces: [simd_uint3]) -> [Float] {
        guard !faces.isEmpty else { return [] }

        var areas = [Float](repeating: 0, count: faces.count)

        for (index, face) in faces.enumerated() {
            let v0 = vertices[Int(face.x)]
            let v1 = vertices[Int(face.y)]
            let v2 = vertices[Int(face.z)]
            areas[index] = triangleArea(v0: v0, v1: v1, v2: v2)
        }

        return areas
    }

    // MARK: - Private Helpers

    /// 2D Shoelace formula applied to two selected axes from 3D points.
    /// The axis KeyPaths determine which two components are used for the 2D projection.
    private static func shoelaceArea2D(
        _ points: [simd_float3],
        axis1: KeyPath<simd_float3, Float>,
        axis2: KeyPath<simd_float3, Float>
    ) -> Float {
        guard points.count >= 3 else { return 0 }

        var area: Float = 0
        let n = points.count

        for i in 0..<n {
            let j = (i + 1) % n
            let xi = points[i][keyPath: axis1]
            let yi = points[i][keyPath: axis2]
            let xj = points[j][keyPath: axis1]
            let yj = points[j][keyPath: axis2]

            area += xi * yj
            area -= xj * yi
        }

        return abs(area) / 2.0
    }
}
