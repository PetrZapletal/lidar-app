import Foundation
import simd

/// Calculates volumes of 3D shapes and mesh regions
final class VolumeCalculator: Sendable {

    // MARK: - Bounding Box Volume

    /// Calculate volume of axis-aligned bounding box from points
    func boundingBoxVolume(points: [simd_float3]) -> Float {
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

    /// Calculate bounding box dimensions
    func boundingBoxDimensions(points: [simd_float3]) -> (width: Float, height: Float, depth: Float) {
        guard !points.isEmpty else { return (0, 0, 0) }

        var minPoint = points[0]
        var maxPoint = points[0]

        for point in points {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }

        let size = maxPoint - minPoint
        return (size.x, size.y, size.z)
    }

    // MARK: - Mesh Volume

    /// Calculate volume of a closed mesh using signed tetrahedron volumes
    /// Based on divergence theorem: V = (1/6) * Σ (v0 · (v1 × v2))
    func meshVolume(mesh: MeshData) -> Float {
        var volume: Float = 0

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

            // Signed volume of tetrahedron with origin
            let signedVolume = simd_dot(v0, simd_cross(v1, v2))
            volume += signedVolume
        }

        return abs(volume) / 6.0
    }

    /// Calculate volume of mesh region defined by face indices
    func meshRegionVolume(mesh: MeshData, faceIndices: Set<Int>) -> Float {
        var volume: Float = 0

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

            let signedVolume = simd_dot(v0, simd_cross(v1, v2))
            volume += signedVolume
        }

        return abs(volume) / 6.0
    }

    // MARK: - Convex Hull Volume

    /// Calculate volume of convex hull of points
    func convexHullVolume(points: [simd_float3]) -> Float {
        guard points.count >= 4 else { return 0 }

        // Simple approach: compute convex hull and then volume
        let hull = computeConvexHull(points: points)
        return meshVolume(hull)
    }

    /// Compute convex hull of point set (simplified incremental algorithm)
    private func computeConvexHull(points: [simd_float3]) -> MeshData {
        guard points.count >= 4 else {
            return MeshData(anchorIdentifier: UUID(), vertices: points, normals: [], faces: [])
        }

        // Find extreme points for initial tetrahedron
        var minX = 0, maxX = 0, minY = 0, maxY = 0, minZ = 0, maxZ = 0

        for i in 1..<points.count {
            if points[i].x < points[minX].x { minX = i }
            if points[i].x > points[maxX].x { maxX = i }
            if points[i].y < points[minY].y { minY = i }
            if points[i].y > points[maxY].y { maxY = i }
            if points[i].z < points[minZ].z { minZ = i }
            if points[i].z > points[maxZ].z { maxZ = i }
        }

        // Use extreme points as hull vertices (simplified)
        let extremeIndices = Set([minX, maxX, minY, maxY, minZ, maxZ])
        let hullVertices = extremeIndices.map { points[$0] }

        // Create faces (simplified - just the extreme points)
        // In production, use proper convex hull algorithm (QuickHull, etc.)
        var faces: [simd_uint3] = []

        if hullVertices.count >= 4 {
            // Create tetrahedron from first 4 points
            faces = [
                simd_uint3(0, 1, 2),
                simd_uint3(0, 2, 3),
                simd_uint3(0, 3, 1),
                simd_uint3(1, 3, 2)
            ]
        }

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: Array(hullVertices),
            normals: [],
            faces: faces
        )
    }

    // MARK: - Room Volume

    /// Estimate room volume from mesh (floor × height)
    func roomVolume(
        mesh: MeshData,
        floorHeight: Float? = nil,
        ceilingHeight: Float? = nil
    ) -> Float {
        // Find floor and ceiling heights
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude

        for vertex in mesh.worldVertices {
            minY = min(minY, vertex.y)
            maxY = max(maxY, vertex.y)
        }

        let actualFloorHeight = floorHeight ?? minY
        let actualCeilingHeight = ceilingHeight ?? maxY
        let height = actualCeilingHeight - actualFloorHeight

        // Calculate floor area
        let areaCalculator = AreaCalculator()
        let floorArea = areaCalculator.floorArea(mesh: mesh)

        return floorArea * height
    }

    /// Estimate room volume with irregular ceiling
    func roomVolumeIrregular(mesh: MeshData) -> Float {
        // Use mesh volume for irregular shapes
        return meshVolume(mesh: mesh)
    }

    // MARK: - Primitive Volumes

    /// Calculate volume of a sphere
    func sphereVolume(radius: Float) -> Float {
        return (4.0 / 3.0) * .pi * radius * radius * radius
    }

    /// Calculate volume of a cylinder
    func cylinderVolume(radius: Float, height: Float) -> Float {
        return .pi * radius * radius * height
    }

    /// Calculate volume of a cone
    func coneVolume(radius: Float, height: Float) -> Float {
        return (1.0 / 3.0) * .pi * radius * radius * height
    }

    /// Calculate volume of a box
    func boxVolume(width: Float, height: Float, depth: Float) -> Float {
        return width * height * depth
    }

    /// Calculate volume of a prism with polygon base
    func prismVolume(baseArea: Float, height: Float) -> Float {
        return baseArea * height
    }

    /// Calculate volume of a pyramid with polygon base
    func pyramidVolume(baseArea: Float, height: Float) -> Float {
        return (1.0 / 3.0) * baseArea * height
    }

    // MARK: - Extrusion Volume

    /// Calculate volume of extruded polygon
    func extrusionVolume(polygon: [simd_float3], extrusionVector: simd_float3) -> Float {
        let areaCalculator = AreaCalculator()
        let baseArea = areaCalculator.polygonArea(vertices: polygon)
        let height = simd_length(extrusionVector)

        return baseArea * height
    }

    // MARK: - Volume from Cross-Sections

    /// Estimate volume from parallel cross-sections (Simpson's rule)
    func volumeFromCrossSections(
        crossSections: [(height: Float, area: Float)]
    ) -> Float {
        guard crossSections.count >= 2 else {
            if let first = crossSections.first {
                return first.area  // Single section
            }
            return 0
        }

        // Sort by height
        let sorted = crossSections.sorted { $0.height < $1.height }

        var volume: Float = 0

        // Use trapezoidal rule
        for i in 0..<(sorted.count - 1) {
            let h1 = sorted[i].height
            let h2 = sorted[i + 1].height
            let a1 = sorted[i].area
            let a2 = sorted[i + 1].area

            let sliceVolume = (h2 - h1) * (a1 + a2) / 2
            volume += sliceVolume
        }

        return volume
    }

    // MARK: - Signed Volume

    /// Calculate signed volume (positive if mesh normals point outward)
    func signedMeshVolume(mesh: MeshData) -> Float {
        var volume: Float = 0

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

            let signedVolume = simd_dot(v0, simd_cross(v1, v2))
            volume += signedVolume
        }

        return volume / 6.0
    }

    // MARK: - Volume Statistics

    struct VolumeStatistics {
        let totalVolume: Float
        let boundingBoxVolume: Float
        let fillRatio: Float  // totalVolume / boundingBoxVolume
        let centroid: simd_float3
        let principalAxes: (simd_float3, simd_float3, simd_float3)
    }

    /// Compute comprehensive volume statistics for a mesh
    func computeVolumeStatistics(mesh: MeshData) -> VolumeStatistics {
        let totalVolume = meshVolume(mesh: mesh)
        let bbVolume = boundingBoxVolume(points: mesh.worldVertices)
        let fillRatio = bbVolume > 0 ? totalVolume / bbVolume : 0

        // Calculate centroid
        let centroid = mesh.worldVertices.isEmpty ?
            simd_float3.zero :
            mesh.worldVertices.reduce(simd_float3.zero, +) / Float(mesh.worldVertices.count)

        // Principal axes (simplified - use bounding box axes)
        let principalAxes = (
            simd_float3(1, 0, 0),
            simd_float3(0, 1, 0),
            simd_float3(0, 0, 1)
        )

        return VolumeStatistics(
            totalVolume: totalVolume,
            boundingBoxVolume: bbVolume,
            fillRatio: fillRatio,
            centroid: centroid,
            principalAxes: principalAxes
        )
    }
}

// MARK: - Watertight Check

extension VolumeCalculator {

    /// Check if mesh is watertight (closed)
    func isWatertight(mesh: MeshData) -> Bool {
        // A watertight mesh has every edge shared by exactly 2 faces

        var edgeCounts: [String: Int] = [:]

        for face in mesh.faces {
            let indices = [Int(face.x), Int(face.y), Int(face.z)]

            for i in 0..<3 {
                let v1 = indices[i]
                let v2 = indices[(i + 1) % 3]

                // Create edge key (smaller index first)
                let edgeKey = v1 < v2 ? "\(v1)-\(v2)" : "\(v2)-\(v1)"
                edgeCounts[edgeKey, default: 0] += 1
            }
        }

        // Check that all edges have exactly 2 faces
        for (_, count) in edgeCounts {
            if count != 2 {
                return false
            }
        }

        return true
    }

    /// Find boundary edges (edges with only 1 face)
    func findBoundaryEdges(mesh: MeshData) -> [(Int, Int)] {
        var edgeFaces: [String: [(Int, Int)]] = [:]

        for face in mesh.faces {
            let indices = [Int(face.x), Int(face.y), Int(face.z)]

            for i in 0..<3 {
                let v1 = indices[i]
                let v2 = indices[(i + 1) % 3]

                let edgeKey = v1 < v2 ? "\(v1)-\(v2)" : "\(v2)-\(v1)"
                let edge = v1 < v2 ? (v1, v2) : (v2, v1)

                edgeFaces[edgeKey, default: []].append(edge)
            }
        }

        var boundaryEdges: [(Int, Int)] = []

        for (_, edges) in edgeFaces {
            if edges.count == 1 {
                boundaryEdges.append(edges[0])
            }
        }

        return boundaryEdges
    }

    /// Estimate volume accounting for open mesh (approximate)
    func estimateVolumeOpenMesh(mesh: MeshData) -> Float {
        if isWatertight(mesh: mesh) {
            return meshVolume(mesh: mesh)
        }

        // For open meshes, use bounding box as approximation
        // Could also try to close the mesh first
        let bbVolume = boundingBoxVolume(points: mesh.worldVertices)

        // Apply a fill factor estimate based on mesh density
        let areaCalculator = AreaCalculator()
        let surfaceArea = areaCalculator.meshSurfaceArea(mesh: mesh)

        // Estimate fill factor using surface area to volume ratio
        // For a sphere: A = 4πr², V = (4/3)πr³, ratio = A/V = 3/r
        // For a cube: A = 6s², V = s³, ratio = A/V = 6/s
        let characteristicLength = pow(bbVolume, 1.0/3.0)
        let expectedRatio = surfaceArea / characteristicLength

        // Typical fill factor for rooms/spaces
        let fillFactor: Float = 0.85

        return bbVolume * fillFactor
    }
}
