import XCTest
import simd
@testable import LidarAPP

final class PointCloudTests: XCTestCase {

    // MARK: - Initialization Tests

    func testPointCloudInitialization() {
        // Given
        let points: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(1, 0, 0),
            simd_float3(0, 1, 0)
        ]

        // When
        let pointCloud = PointCloud(points: points)

        // Then
        XCTAssertEqual(pointCloud.pointCount, 3)
        XCTAssertNil(pointCloud.colors)
        XCTAssertNil(pointCloud.normals)
        XCTAssertNil(pointCloud.confidences)
    }

    func testPointCloudWithColors() {
        // Given
        let points: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(1, 0, 0)
        ]
        let colors: [simd_float4] = [
            simd_float4(1, 0, 0, 1),
            simd_float4(0, 1, 0, 1)
        ]

        // When
        let pointCloud = PointCloud(points: points, colors: colors)

        // Then
        XCTAssertNotNil(pointCloud.colors)
        XCTAssertEqual(pointCloud.colors?.count, 2)
    }

    // MARK: - Bounding Box Tests

    func testBoundingBox() {
        // Given
        let points: [simd_float3] = [
            simd_float3(-1, -2, -3),
            simd_float3(4, 5, 6),
            simd_float3(0, 0, 0)
        ]

        // When
        let pointCloud = PointCloud(points: points)
        let boundingBox = pointCloud.boundingBox

        // Then
        XCTAssertNotNil(boundingBox)
        XCTAssertEqual(Double(boundingBox?.min.x ?? 0), -1, accuracy: 0.001)
        XCTAssertEqual(Double(boundingBox?.min.y ?? 0), -2, accuracy: 0.001)
        XCTAssertEqual(Double(boundingBox?.min.z ?? 0), -3, accuracy: 0.001)
        XCTAssertEqual(Double(boundingBox?.max.x ?? 0), 4, accuracy: 0.001)
        XCTAssertEqual(Double(boundingBox?.max.y ?? 0), 5, accuracy: 0.001)
        XCTAssertEqual(Double(boundingBox?.max.z ?? 0), 6, accuracy: 0.001)
    }

    func testBoundingBoxSize() {
        // Given
        let points: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(2, 3, 4)
        ]

        // When
        let pointCloud = PointCloud(points: points)
        let size = pointCloud.boundingBox?.size

        // Then
        XCTAssertEqual(Double(size?.x ?? 0), 2, accuracy: 0.001)
        XCTAssertEqual(Double(size?.y ?? 0), 3, accuracy: 0.001)
        XCTAssertEqual(Double(size?.z ?? 0), 4, accuracy: 0.001)
    }

    func testBoundingBoxVolume() {
        // Given
        let points: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(2, 3, 4)
        ]

        // When
        let pointCloud = PointCloud(points: points)
        let volume = pointCloud.boundingBox?.volume

        // Then
        XCTAssertEqual(Double(volume ?? 0), 24, accuracy: 0.001)  // 2 * 3 * 4 = 24
    }

    func testEmptyPointCloudBoundingBox() {
        // Given/When
        let pointCloud = PointCloud(points: [])

        // Then
        XCTAssertNil(pointCloud.boundingBox)
    }

    // MARK: - Centroid Tests

    func testCentroid() {
        // Given
        let points: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(2, 0, 0),
            simd_float3(0, 3, 0),
            simd_float3(0, 0, 4)
        ]

        // When
        let pointCloud = PointCloud(points: points)
        let centroid = pointCloud.centroid

        // Then
        XCTAssertEqual(Double(centroid.x), 0.5, accuracy: 0.001)
        XCTAssertEqual(Double(centroid.y), 0.75, accuracy: 0.001)
        XCTAssertEqual(Double(centroid.z), 1.0, accuracy: 0.001)
    }

    func testEmptyPointCloudCentroid() {
        // Given/When
        let pointCloud = PointCloud(points: [])

        // Then
        XCTAssertEqual(pointCloud.centroid, simd_float3.zero)
    }

    // MARK: - Merge Tests

    func testMergePointClouds() {
        // Given
        let points1: [simd_float3] = [simd_float3(0, 0, 0), simd_float3(1, 0, 0)]
        let points2: [simd_float3] = [simd_float3(2, 0, 0), simd_float3(3, 0, 0)]
        let cloud1 = PointCloud(points: points1)
        let cloud2 = PointCloud(points: points2)

        // When
        let merged = cloud1.merged(with: cloud2)

        // Then
        XCTAssertEqual(merged.pointCount, 4)
    }

    func testMergePointCloudsWithColors() {
        // Given
        let points1: [simd_float3] = [simd_float3(0, 0, 0)]
        let colors1: [simd_float4] = [simd_float4(1, 0, 0, 1)]
        let points2: [simd_float3] = [simd_float3(1, 0, 0)]
        let colors2: [simd_float4] = [simd_float4(0, 1, 0, 1)]

        let cloud1 = PointCloud(points: points1, colors: colors1)
        let cloud2 = PointCloud(points: points2, colors: colors2)

        // When
        let merged = cloud1.merged(with: cloud2)

        // Then
        XCTAssertEqual(merged.colors?.count, 2)
    }

    // MARK: - Filter Tests

    func testFilterByConfidence() {
        // Given
        let points: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(1, 0, 0),
            simd_float3(2, 0, 0)
        ]
        let confidences: [Float] = [0.3, 0.7, 0.9]
        let cloud = PointCloud(points: points, confidences: confidences)

        // When
        let filtered = cloud.filtered(minConfidence: 0.5)

        // Then
        XCTAssertEqual(filtered.pointCount, 2)
    }

    func testFilterWithNoConfidences() {
        // Given
        let points: [simd_float3] = [simd_float3(0, 0, 0)]
        let cloud = PointCloud(points: points)

        // When
        let filtered = cloud.filtered(minConfidence: 0.5)

        // Then - should return unchanged
        XCTAssertEqual(filtered.pointCount, 1)
    }

    // MARK: - Transformation Tests

    func testTranslation() {
        // Given
        let points: [simd_float3] = [simd_float3(0, 0, 0)]
        let cloud = PointCloud(points: points)

        var translation = matrix_identity_float4x4
        translation.columns.3 = simd_float4(1, 2, 3, 1)

        // When
        let transformed = cloud.transformed(by: translation)

        // Then
        XCTAssertEqual(Double(transformed.points[0].x), 1, accuracy: 0.001)
        XCTAssertEqual(Double(transformed.points[0].y), 2, accuracy: 0.001)
        XCTAssertEqual(Double(transformed.points[0].z), 3, accuracy: 0.001)
    }
}

// MARK: - BoundingBox Tests

final class BoundingBoxTests: XCTestCase {

    func testCenter() {
        // Given
        let bbox = BoundingBox(
            min: simd_float3(0, 0, 0),
            max: simd_float3(2, 4, 6)
        )

        // Then
        XCTAssertEqual(Double(bbox.center.x), 1, accuracy: 0.001)
        XCTAssertEqual(Double(bbox.center.y), 2, accuracy: 0.001)
        XCTAssertEqual(Double(bbox.center.z), 3, accuracy: 0.001)
    }

    func testDiagonal() {
        // Given
        let bbox = BoundingBox(
            min: simd_float3(0, 0, 0),
            max: simd_float3(3, 4, 0)  // 3-4-5 triangle
        )

        // Then
        XCTAssertEqual(Double(bbox.diagonal), 5, accuracy: 0.001)
    }
}
