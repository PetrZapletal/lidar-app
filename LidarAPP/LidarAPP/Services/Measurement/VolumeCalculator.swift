import Foundation
import simd

/// Volume calculations from mesh data and point sets.
/// Implements signed tetrahedron volume (divergence theorem),
/// bounding box volume, convex hull approximation, and room estimation.
struct VolumeCalculator {

    // MARK: - Mesh Volume (Divergence Theorem)

    /// Calculate the volume of a closed mesh using the signed tetrahedron method.
    /// Each triangle face forms a tetrahedron with the origin; the signed volume
    /// of all such tetrahedra sums to the mesh volume (for a closed, consistently-wound mesh).
    /// Returns the absolute value to handle winding direction.
    static func meshVolume(meshData: MeshData) -> Float {
        guard !meshData.vertices.isEmpty, !meshData.faces.isEmpty else { return 0 }

        let worldVerts = meshData.worldVertices

        var signedVolume: Float = 0

        for face in meshData.faces {
            let v0 = worldVerts[Int(face.x)]
            let v1 = worldVerts[Int(face.y)]
            let v2 = worldVerts[Int(face.z)]

            // Signed volume of tetrahedron formed with origin
            // V = dot(v0, cross(v1, v2)) / 6
            signedVolume += simd_dot(v0, simd_cross(v1, v2)) / 6.0
        }

        return abs(signedVolume)
    }

    // MARK: - Bounding Box Volume

    /// Calculate the axis-aligned bounding box volume of a mesh.
    /// This is always >= the actual mesh volume.
    static func boundingBoxVolume(meshData: MeshData) -> Float {
        guard let bbox = meshData.boundingBox else { return 0 }
        return bbox.volume
    }

    /// Calculate the axis-aligned bounding box volume from a set of points.
    static func boundingBoxVolume(points: [simd_float3]) -> Float {
        guard !points.isEmpty else { return 0 }

        var minPoint = points[0]
        var maxPoint = points[0]

        for point in points {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }

        let size = maxPoint - minPoint
        return size.x * size.y * size.z
    }

    // MARK: - Convex Hull Volume (Approximation)

    /// Approximate the convex hull volume of a point set.
    /// Uses the gift-wrapping derived approach: compute the centroid,
    /// then sum signed tetrahedra volumes from the centroid to each face
    /// of a simplified convex hull (PCA-aligned bounding box approximation).
    ///
    /// For a full convex hull, a dedicated algorithm (QuickHull) would be needed.
    /// This provides a reasonable volumetric estimate using the oriented bounding box.
    static func convexHullVolume(points: [simd_float3]) -> Float {
        guard points.count >= 4 else { return 0 }

        // Compute centroid
        var centroid = simd_float3.zero
        for point in points {
            centroid += point
        }
        centroid /= Float(points.count)

        // Compute covariance matrix for PCA
        var cxx: Float = 0; var cxy: Float = 0; var cxz: Float = 0
        var cyy: Float = 0; var cyz: Float = 0
        var czz: Float = 0

        for point in points {
            let d = point - centroid
            cxx += d.x * d.x
            cxy += d.x * d.y
            cxz += d.x * d.z
            cyy += d.y * d.y
            cyz += d.y * d.z
            czz += d.z * d.z
        }

        let n = Float(points.count)
        cxx /= n; cxy /= n; cxz /= n
        cyy /= n; cyz /= n; czz /= n

        // Use the covariance eigenvalues to estimate the oriented bounding box dimensions.
        // For a rough estimate, use the principal axis lengths derived from variance.
        // Trace and determinant of covariance give us the spread.
        let trace = cxx + cyy + czz
        let detXY = cxx * cyy - cxy * cxy
        let detXZ = cxx * czz - cxz * cxz
        let detYZ = cyy * czz - cyz * cyz

        // Sum of minors
        let q = (cxx + cyy + czz) / 3.0
        let p2 = (cxx - q) * (cxx - q) + (cyy - q) * (cyy - q) + (czz - q) * (czz - q)
            + 2.0 * (cxy * cxy + cxz * cxz + cyz * cyz)
        let p = sqrtf(p2 / 6.0)

        guard p > .ulpOfOne else {
            // Degenerate -- points are collinear or coincident
            return 0
        }

        // For the OBB approximation, project points along the principal axes
        // and compute the extent along each. A simple approximation:
        // find the min/max extent along each of 3 mutually orthogonal directions.

        // Primary axis: direction of maximum variance (power iteration approximation)
        var axis = simd_float3(1, 0, 0)
        for _ in 0..<10 {
            let next = simd_float3(
                cxx * axis.x + cxy * axis.y + cxz * axis.z,
                cxy * axis.x + cyy * axis.y + cyz * axis.z,
                cxz * axis.x + cyz * axis.y + czz * axis.z
            )
            let len = simd_length(next)
            if len > .ulpOfOne {
                axis = next / len
            }
        }

        // Build orthonormal basis
        let primaryAxis = axis
        let secondaryAxis = orthogonalVector(to: primaryAxis)
        let tertiaryAxis = simd_cross(primaryAxis, secondaryAxis)

        // Project all points and find extents
        var minProj = simd_float3(Float.greatestFiniteMagnitude,
                                   Float.greatestFiniteMagnitude,
                                   Float.greatestFiniteMagnitude)
        var maxProj = simd_float3(-Float.greatestFiniteMagnitude,
                                   -Float.greatestFiniteMagnitude,
                                   -Float.greatestFiniteMagnitude)

        for point in points {
            let d = point - centroid
            let proj = simd_float3(
                simd_dot(d, primaryAxis),
                simd_dot(d, secondaryAxis),
                simd_dot(d, tertiaryAxis)
            )
            minProj = simd_min(minProj, proj)
            maxProj = simd_max(maxProj, proj)
        }

        let extent = maxProj - minProj

        // Convex hull is roughly 2/3 the OBB volume for typical shapes
        // (sphere in box ratio is pi/6 ~ 0.524, convex hull is between that and 1.0)
        let obbVolume = extent.x * extent.y * extent.z
        let convexHullEstimate = obbVolume * 0.667

        return max(0, convexHullEstimate)
    }

    // MARK: - Room Volume Estimation

    /// Estimate room volume from floor area and ceiling height.
    /// Simple box-model approximation suitable for rectangular rooms.
    static func roomVolume(floorArea: Float, ceilingHeight: Float) -> Float {
        return floorArea * ceilingHeight
    }

    /// Estimate room volume from mesh data by detecting floor and ceiling planes.
    /// Uses the vertical (Y-axis) extent of the mesh as an approximation for ceiling height,
    /// and the floor area from the XZ bounding box.
    static func estimateRoomVolume(meshData: MeshData) -> Float {
        guard let bbox = meshData.boundingBox else { return 0 }

        let height = bbox.size.y
        let floorArea = bbox.size.x * bbox.size.z

        // Use 85% of bounding box volume as room volume estimate
        // (accounts for non-rectangular walls, furniture, etc.)
        return floorArea * height * 0.85
    }

    // MARK: - Private Helpers

    /// Find a vector orthogonal to the given vector
    private static func orthogonalVector(to v: simd_float3) -> simd_float3 {
        let absV = simd_abs(v)

        // Choose the axis least aligned with v for the cross product
        let reference: simd_float3
        if absV.x <= absV.y && absV.x <= absV.z {
            reference = simd_float3(1, 0, 0)
        } else if absV.y <= absV.x && absV.y <= absV.z {
            reference = simd_float3(0, 1, 0)
        } else {
            reference = simd_float3(0, 0, 1)
        }

        let ortho = simd_cross(v, reference)
        let len = simd_length(ortho)

        guard len > .ulpOfOne else {
            return simd_float3(0, 1, 0)
        }

        return ortho / len
    }
}
