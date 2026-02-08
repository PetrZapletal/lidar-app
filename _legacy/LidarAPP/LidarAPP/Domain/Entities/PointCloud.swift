import Foundation
import simd
import QuartzCore

/// Represents a 3D point cloud captured from LiDAR
struct PointCloud: Identifiable, Sendable {
    let id: UUID
    let points: [simd_float3]
    let colors: [simd_float4]?
    let normals: [simd_float3]?
    let confidences: [Float]?
    let timestamp: TimeInterval
    let metadata: PointCloudMetadata

    init(
        id: UUID = UUID(),
        points: [simd_float3],
        colors: [simd_float4]? = nil,
        normals: [simd_float3]? = nil,
        confidences: [Float]? = nil,
        timestamp: TimeInterval = CACurrentMediaTime(),
        metadata: PointCloudMetadata = PointCloudMetadata()
    ) {
        self.id = id
        self.points = points
        self.colors = colors
        self.normals = normals
        self.confidences = confidences
        self.timestamp = timestamp
        self.metadata = metadata
    }

    // MARK: - Computed Properties

    var pointCount: Int { points.count }

    var boundingBox: BoundingBox? {
        guard !points.isEmpty else { return nil }

        var minPoint = points[0]
        var maxPoint = points[0]

        for point in points {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }

        return BoundingBox(min: minPoint, max: maxPoint)
    }

    var centroid: simd_float3 {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(simd_float3.zero, +)
        return sum / Float(points.count)
    }

    // MARK: - Transformations

    func transformed(by matrix: simd_float4x4) -> PointCloud {
        let transformedPoints = points.map { point -> simd_float3 in
            let homogeneous = simd_float4(point.x, point.y, point.z, 1)
            let result = matrix * homogeneous
            return simd_float3(result.x, result.y, result.z)
        }

        let transformedNormals = normals?.map { normal -> simd_float3 in
            let normalMatrix = simd_float3x3(
                simd_float3(matrix[0].x, matrix[0].y, matrix[0].z),
                simd_float3(matrix[1].x, matrix[1].y, matrix[1].z),
                simd_float3(matrix[2].x, matrix[2].y, matrix[2].z)
            )
            return simd_normalize(normalMatrix * normal)
        }

        return PointCloud(
            id: id,
            points: transformedPoints,
            colors: colors,
            normals: transformedNormals,
            confidences: confidences,
            timestamp: timestamp,
            metadata: metadata
        )
    }

    // MARK: - Merging

    func merged(with other: PointCloud) -> PointCloud {
        var mergedPoints = points
        mergedPoints.append(contentsOf: other.points)

        var mergedColors: [simd_float4]?
        if let c1 = colors, let c2 = other.colors {
            mergedColors = c1 + c2
        }

        var mergedNormals: [simd_float3]?
        if let n1 = normals, let n2 = other.normals {
            mergedNormals = n1 + n2
        }

        var mergedConfidences: [Float]?
        if let conf1 = confidences, let conf2 = other.confidences {
            mergedConfidences = conf1 + conf2
        }

        return PointCloud(
            points: mergedPoints,
            colors: mergedColors,
            normals: mergedNormals,
            confidences: mergedConfidences,
            timestamp: max(timestamp, other.timestamp),
            metadata: metadata
        )
    }

    // MARK: - Filtering

    func filtered(minConfidence: Float) -> PointCloud {
        guard let confidences = confidences else { return self }

        var filteredPoints: [simd_float3] = []
        var filteredColors: [simd_float4]?
        var filteredNormals: [simd_float3]?
        var filteredConfidences: [Float] = []

        if colors != nil { filteredColors = [] }
        if normals != nil { filteredNormals = [] }

        for (index, confidence) in confidences.enumerated() {
            if confidence >= minConfidence {
                filteredPoints.append(points[index])
                filteredConfidences.append(confidence)
                if let colors = colors { filteredColors?.append(colors[index]) }
                if let normals = normals { filteredNormals?.append(normals[index]) }
            }
        }

        return PointCloud(
            id: id,
            points: filteredPoints,
            colors: filteredColors,
            normals: filteredNormals,
            confidences: filteredConfidences,
            timestamp: timestamp,
            metadata: metadata
        )
    }
}

// MARK: - Supporting Types

struct PointCloudMetadata: Sendable {
    var source: PointCloudSource = .lidar
    var coordinateSystem: CoordinateSystem = .arkit
    var unit: MeasurementUnit = .meters

    enum PointCloudSource: String, Sendable {
        case lidar
        case photogrammetry
        case imported
    }

    enum CoordinateSystem: String, Sendable {
        case arkit  // Y-up, right-handed
        case opengl
        case custom
    }

    enum MeasurementUnit: String, Sendable {
        case meters
        case centimeters
        case millimeters
    }
}

struct BoundingBox: Sendable {
    let min: simd_float3
    let max: simd_float3

    var size: simd_float3 {
        max - min
    }

    var center: simd_float3 {
        (min + max) / 2
    }

    var volume: Float {
        let s = size
        return s.x * s.y * s.z
    }

    var diagonal: Float {
        simd_length(size)
    }
}
