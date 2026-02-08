import XCTest
import simd
@testable import LidarAPP

/// Integration tests for the LiDAR Scanner app
final class IntegrationTests: XCTestCase {

    // MARK: - Scan Workflow Tests

    func testCompleteScanWorkflow() {
        // Given - Create a scan session
        let session = ScanSession(name: "Integration Test Scan")
        XCTAssertEqual(session.state, .idle)

        // When - Start scanning
        session.startScanning()
        XCTAssertEqual(session.state, .scanning)

        // Simulate adding point cloud data
        let mockProvider = MockDataProvider.shared
        let pointCloud = mockProvider.generateRoomPointCloud()
        session.pointCloud = pointCloud
        XCTAssertNotNil(session.pointCloud)

        // Simulate adding mesh data
        let mesh = mockProvider.generateSampleMesh()
        session.addMesh(mesh)
        XCTAssertGreaterThan(session.combinedMesh.meshes.count, 0)

        // When - Stop scanning
        session.stopScanning()

        // Then
        XCTAssertEqual(session.state, .completed)
        XCTAssertGreaterThan(session.vertexCount, 0)
        XCTAssertGreaterThan(session.faceCount, 0)
    }

    func testMeasurementWorkflow() {
        // Given
        let session = ScanSession(name: "Measurement Test")

        // When - Add various measurements
        let distanceMeasurement = Measurement(
            type: .distance,
            points: [simd_float3(0, 0, 0), simd_float3(2.5, 0, 0)],
            value: 2.5,
            unit: .meters,
            label: "Wall width"
        )
        session.addMeasurement(distanceMeasurement)

        let areaMeasurement = Measurement(
            type: .area,
            points: [
                simd_float3(0, 0, 0),
                simd_float3(4, 0, 0),
                simd_float3(4, 0, 3),
                simd_float3(0, 0, 3)
            ],
            value: 12.0,
            unit: .meters,
            label: "Floor area"
        )
        session.addMeasurement(areaMeasurement)

        // Then
        XCTAssertEqual(session.measurements.count, 2)
        XCTAssertEqual(session.measurements[0].formattedValue, "2.50 m")
        XCTAssertEqual(session.measurements[1].type, .area)
    }

    func testScanSessionPauseResume() {
        // Given
        let session = ScanSession(name: "Pause Test")
        session.startScanning()

        // When
        session.pauseScanning()
        XCTAssertEqual(session.state, .paused)

        session.resumeScanning()
        XCTAssertEqual(session.state, .scanning)

        session.stopScanning()

        // Then
        XCTAssertEqual(session.state, .completed)
    }

    // MARK: - Data Persistence Tests

    func testPointCloudSerialization() {
        // Given
        let originalPoints: [simd_float3] = [
            simd_float3(1, 2, 3),
            simd_float3(4, 5, 6)
        ]
        let originalColors: [simd_float4] = [
            simd_float4(1, 0, 0, 1),
            simd_float4(0, 1, 0, 1)
        ]
        let pointCloud = PointCloud(points: originalPoints, colors: originalColors)

        // Then - Verify data integrity
        XCTAssertEqual(pointCloud.pointCount, 2)
        XCTAssertEqual(Double(pointCloud.points[0].x), 1, accuracy: 0.001)
        XCTAssertEqual(Double(pointCloud.colors?[1].y ?? 0), 1, accuracy: 0.001)
    }

    func testMeshDataIntegrity() {
        // Given
        let mockProvider = MockDataProvider.shared
        let mesh = mockProvider.generateFloorMesh(width: 4, depth: 5, subdivisions: 10)

        // Then
        XCTAssertEqual(mesh.surfaceArea, 20, accuracy: 0.1)  // 4 * 5 = 20 m²

        // Verify all faces reference valid vertices
        let maxIndex = mesh.vertices.count - 1
        for face in mesh.faces {
            XCTAssertLessThanOrEqual(Int(face.x), maxIndex)
            XCTAssertLessThanOrEqual(Int(face.y), maxIndex)
            XCTAssertLessThanOrEqual(Int(face.z), maxIndex)
        }
    }

    // MARK: - Unit Conversion Tests

    func testUnitConversionRoundtrip() {
        // Given
        let originalMeters: Float = 1.0

        // When - Convert through all units and back
        let toCm = MeasurementUnit.centimeters.convert(originalMeters, from: .meters)
        let toFeet = MeasurementUnit.feet.convert(originalMeters, from: .meters)
        let toInches = MeasurementUnit.inches.convert(originalMeters, from: .meters)

        let backFromCm = MeasurementUnit.meters.convert(toCm, from: .centimeters)
        let backFromFeet = MeasurementUnit.meters.convert(toFeet, from: .feet)
        let backFromInches = MeasurementUnit.meters.convert(toInches, from: .inches)

        // Then
        XCTAssertEqual(Double(backFromCm), Double(originalMeters), accuracy: 0.001)
        XCTAssertEqual(Double(backFromFeet), Double(originalMeters), accuracy: 0.001)
        XCTAssertEqual(Double(backFromInches), Double(originalMeters), accuracy: 0.001)
    }

    // MARK: - Bounding Box Tests

    func testBoundingBoxCalculation() {
        // Given - Room-like point cloud
        let mockProvider = MockDataProvider.shared
        let pointCloud = mockProvider.generateRoomPointCloud(
            width: 4.0,
            height: 2.5,
            depth: 5.0,
            pointDensity: 10000
        )

        // When
        let bbox = pointCloud.boundingBox

        // Then
        XCTAssertNotNil(bbox)
        guard let bb = bbox else { return }

        // Check dimensions are approximately correct
        XCTAssertEqual(bb.size.x, 4.0, accuracy: 0.5)
        XCTAssertEqual(bb.size.y, 2.5, accuracy: 0.5)
        XCTAssertEqual(bb.size.z, 5.0, accuracy: 0.5)

        // Check volume
        let expectedVolume = 4.0 * 2.5 * 5.0  // 50 m³
        XCTAssertEqual(bb.volume, Float(expectedVolume), accuracy: 5.0)
    }

    // MARK: - Combined Mesh Tests

    func testCombinedMeshUnification() {
        // Given
        let combinedMesh = CombinedMesh()

        // Add multiple meshes
        let mesh1 = MeshData(
            anchorIdentifier: UUID(),
            vertices: [simd_float3](repeating: simd_float3(0, 0, 0), count: 100),
            normals: [simd_float3](repeating: simd_float3(0, 1, 0), count: 100),
            faces: [simd_uint3](repeating: simd_uint3(0, 1, 2), count: 30)
        )

        let mesh2 = MeshData(
            anchorIdentifier: UUID(),
            vertices: [simd_float3](repeating: simd_float3(1, 1, 1), count: 200),
            normals: [simd_float3](repeating: simd_float3(0, 0, 1), count: 200),
            faces: [simd_uint3](repeating: simd_uint3(0, 1, 2), count: 60)
        )

        // When
        combinedMesh.addOrUpdate(mesh1)
        combinedMesh.addOrUpdate(mesh2)

        // Then
        XCTAssertEqual(combinedMesh.totalVertexCount, 300)
        XCTAssertEqual(combinedMesh.totalFaceCount, 90)

        // Test unification
        let unified = combinedMesh.toUnifiedMesh()
        XCTAssertNotNil(unified)
        XCTAssertEqual(unified?.vertexCount, 300)
        XCTAssertEqual(unified?.faceCount, 90)
    }

    // MARK: - Point Cloud Operations Tests

    func testPointCloudFiltering() {
        // Given - Point cloud with varying confidence
        let points: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(1, 0, 0),
            simd_float3(2, 0, 0),
            simd_float3(3, 0, 0)
        ]
        let confidences: [Float] = [0.2, 0.5, 0.8, 0.9]
        let pointCloud = PointCloud(points: points, confidences: confidences)

        // When - Filter by confidence
        let filtered = pointCloud.filtered(minConfidence: 0.7)

        // Then - Only high confidence points remain
        XCTAssertEqual(filtered.pointCount, 2)
    }

    func testPointCloudMerging() {
        // Given
        let cloud1 = PointCloud(
            points: [simd_float3(0, 0, 0), simd_float3(1, 0, 0)],
            colors: [simd_float4(1, 0, 0, 1), simd_float4(0, 1, 0, 1)]
        )
        let cloud2 = PointCloud(
            points: [simd_float3(2, 0, 0), simd_float3(3, 0, 0)],
            colors: [simd_float4(0, 0, 1, 1), simd_float4(1, 1, 0, 1)]
        )

        // When
        let merged = cloud1.merged(with: cloud2)

        // Then
        XCTAssertEqual(merged.pointCount, 4)
        XCTAssertEqual(merged.colors?.count, 4)
    }

    // MARK: - Mock Mode Tests

    func testMockScanSessionComplete() {
        // Given
        let mockProvider = MockDataProvider.shared
        let session = mockProvider.createMockScanSession(name: "Complete Test")

        // Then
        XCTAssertEqual(session.state, .completed)
        XCTAssertNotNil(session.pointCloud)
        XCTAssertGreaterThan(session.combinedMesh.meshes.count, 0)
        XCTAssertGreaterThan(session.measurements.count, 0)

        // Verify measurements are realistic
        for measurement in session.measurements {
            XCTAssertGreaterThan(measurement.value, 0)
            XCTAssertFalse(measurement.formattedValue.isEmpty)
        }
    }
}
