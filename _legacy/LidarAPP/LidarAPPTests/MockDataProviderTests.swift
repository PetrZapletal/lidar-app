import XCTest
import simd
@testable import LidarAPP

final class MockDataProviderTests: XCTestCase {

    var sut: MockDataProvider!

    override func setUp() {
        super.setUp()
        sut = MockDataProvider.shared
    }

    // MARK: - Point Cloud Generation Tests

    func testGenerateSamplePointCloud() {
        // When
        let pointCloud = sut.generateSamplePointCloud(pointCount: 1000)

        // Then
        XCTAssertGreaterThan(pointCloud.pointCount, 0)
        XCTAssertLessThanOrEqual(pointCloud.pointCount, 1000)
        XCTAssertNotNil(pointCloud.colors)
        XCTAssertNotNil(pointCloud.confidences)
    }

    func testGenerateSamplePointCloudColors() {
        // When
        let pointCloud = sut.generateSamplePointCloud(pointCount: 6000)

        // Then - each face has different color
        XCTAssertNotNil(pointCloud.colors)
        guard let colors = pointCloud.colors else { return }

        // Check we have different colors (from different faces)
        let uniqueColors = Set(colors.map { "\($0.x),\($0.y),\($0.z)" })
        XCTAssertGreaterThan(uniqueColors.count, 1)
    }

    func testGenerateSamplePointCloudBoundingBox() {
        // When
        let pointCloud = sut.generateSamplePointCloud(pointCount: 1000)
        let bbox = pointCloud.boundingBox

        // Then - cube should be roughly centered around origin with size ~1
        XCTAssertNotNil(bbox)
        guard let bb = bbox else { return }

        // Size should be approximately 1.0 (with some noise)
        XCTAssertEqual(bb.size.x, 1.0, accuracy: 0.1)
        XCTAssertEqual(bb.size.y, 1.0, accuracy: 0.1)
        XCTAssertEqual(bb.size.z, 1.0, accuracy: 0.1)
    }

    func testGenerateRoomPointCloud() {
        // Given
        let width: Float = 4.0
        let height: Float = 2.5
        let depth: Float = 5.0

        // When
        let pointCloud = sut.generateRoomPointCloud(
            width: width,
            height: height,
            depth: depth,
            pointDensity: 5000
        )

        // Then
        XCTAssertGreaterThan(pointCloud.pointCount, 0)
        XCTAssertNotNil(pointCloud.colors)

        // Check bounding box is roughly room-sized
        if let bbox = pointCloud.boundingBox {
            XCTAssertEqual(bbox.size.x, width, accuracy: 0.5)
            XCTAssertEqual(bbox.size.y, height, accuracy: 0.5)
            XCTAssertEqual(bbox.size.z, depth, accuracy: 0.5)
        }
    }

    // MARK: - Mesh Generation Tests

    func testGenerateSampleMesh() {
        // When
        let mesh = sut.generateSampleMesh()

        // Then - cube has 8 vertices and 12 faces (2 per side * 6 sides)
        XCTAssertEqual(mesh.vertexCount, 8)
        XCTAssertEqual(mesh.faceCount, 12)
        XCTAssertEqual(mesh.normals.count, mesh.vertexCount)
    }

    func testGenerateSampleMeshSurfaceArea() {
        // When
        let mesh = sut.generateSampleMesh()

        // Then - cube with size 0.5 has surface area = 6 * (0.5 * 0.5) = 1.5
        // But wait, the cube has size 0.5 on each side from -0.5 to 0.5, so total side = 1.0
        // Surface area = 6 * 1.0 * 1.0 = 6.0
        XCTAssertEqual(mesh.surfaceArea, 6.0, accuracy: 0.1)
    }

    func testGenerateFloorMesh() {
        // Given
        let width: Float = 4.0
        let depth: Float = 5.0
        let subdivisions = 10

        // When
        let mesh = sut.generateFloorMesh(
            width: width,
            depth: depth,
            subdivisions: subdivisions
        )

        // Then
        let expectedVertices = (subdivisions + 1) * (subdivisions + 1)
        let expectedFaces = subdivisions * subdivisions * 2

        XCTAssertEqual(mesh.vertexCount, expectedVertices)
        XCTAssertEqual(mesh.faceCount, expectedFaces)

        // Check surface area (should be close to width * depth)
        XCTAssertEqual(mesh.surfaceArea, width * depth, accuracy: 0.1)
    }

    func testFloorMeshIsFlat() {
        // When
        let mesh = sut.generateFloorMesh()

        // Then - all Y coordinates should be 0
        for vertex in mesh.vertices {
            XCTAssertEqual(Double(vertex.y), 0, accuracy: 0.001)
        }
    }

    func testFloorMeshNormals() {
        // When
        let mesh = sut.generateFloorMesh()

        // Then - all normals should point up (0, 1, 0)
        for normal in mesh.normals {
            XCTAssertEqual(Double(normal.x), 0, accuracy: 0.001)
            XCTAssertEqual(Double(normal.y), 1, accuracy: 0.001)
            XCTAssertEqual(Double(normal.z), 0, accuracy: 0.001)
        }
    }

    // MARK: - Measurement Generation Tests

    func testGenerateSampleMeasurements() {
        // When
        let measurements = sut.generateSampleMeasurements()

        // Then
        XCTAssertEqual(measurements.count, 4)

        // Check we have all types
        let types = Set(measurements.map { $0.type })
        XCTAssertTrue(types.contains(.distance))
        XCTAssertTrue(types.contains(.area))
        XCTAssertTrue(types.contains(.volume))
    }

    func testMeasurementValues() {
        // When
        let measurements = sut.generateSampleMeasurements()

        // Then
        for measurement in measurements {
            XCTAssertGreaterThan(measurement.value, 0)
            XCTAssertNotNil(measurement.label)
            XCTAssertFalse(measurement.points.isEmpty)
        }
    }

    // MARK: - Scan Session Generation Tests

    func testCreateMockScanSession() {
        // When
        let session = sut.createMockScanSession(name: "Test Session")

        // Then
        XCTAssertEqual(session.name, "Test Session")
        XCTAssertNotNil(session.pointCloud)
        XCTAssertGreaterThan(session.combinedMesh.meshes.count, 0)
        XCTAssertGreaterThan(session.measurements.count, 0)
    }

    func testMockScanSessionState() {
        // When
        let session = sut.createMockScanSession()

        // Then - should be in completed state
        XCTAssertEqual(session.state, .completed)
    }

    func testMockScanSessionData() {
        // When
        let session = sut.createMockScanSession()

        // Then
        XCTAssertGreaterThan(session.vertexCount, 0)
        XCTAssertGreaterThan(session.faceCount, 0)

        if let pc = session.pointCloud {
            XCTAssertGreaterThan(pc.pointCount, 0)
        }
    }

    // MARK: - Mock Mode Tests

    func testMockModeCanBeToggled() {
        // Given
        let originalValue = MockDataProvider.isMockModeEnabled

        // When
        MockDataProvider.isMockModeEnabled = !originalValue

        // Then
        XCTAssertEqual(MockDataProvider.isMockModeEnabled, !originalValue)

        // Cleanup
        MockDataProvider.isMockModeEnabled = originalValue
    }

    func testIsSimulator() {
        // This test verifies the isSimulator property works
        // The actual value depends on where tests are run
        #if targetEnvironment(simulator)
        XCTAssertTrue(MockDataProvider.isSimulator)
        #else
        XCTAssertFalse(MockDataProvider.isSimulator)
        #endif
    }
}
