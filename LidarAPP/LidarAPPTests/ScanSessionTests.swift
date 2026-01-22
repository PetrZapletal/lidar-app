import XCTest
import simd
@testable import LidarAPP

final class ScanSessionTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDefaultInitialization() {
        // When
        let session = ScanSession()

        // Then
        XCTAssertEqual(session.name, "New Scan")
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.pointCloud)
        XCTAssertEqual(session.combinedMesh.meshes.count, 0)
        XCTAssertEqual(session.measurements.count, 0)
        XCTAssertEqual(session.scanDuration, 0)
    }

    func testCustomNameInitialization() {
        // Given
        let name = "Living Room Scan"

        // When
        let session = ScanSession(name: name)

        // Then
        XCTAssertEqual(session.name, name)
    }

    // MARK: - State Management Tests

    func testStartScanning() {
        // Given
        let session = ScanSession()

        // When
        session.startScanning()

        // Then
        XCTAssertEqual(session.state, .scanning)
    }

    func testStartScanningFromPaused() {
        // Given
        let session = ScanSession()
        session.startScanning()
        session.pauseScanning()

        // When
        session.startScanning()

        // Then
        XCTAssertEqual(session.state, .scanning)
    }

    func testCannotStartFromCompleted() {
        // Given
        let session = ScanSession()
        session.startScanning()
        session.stopScanning()

        // When
        session.startScanning()

        // Then - state should remain completed
        XCTAssertEqual(session.state, .completed)
    }

    func testPauseScanning() {
        // Given
        let session = ScanSession()
        session.startScanning()

        // When
        session.pauseScanning()

        // Then
        XCTAssertEqual(session.state, .paused)
    }

    func testCannotPauseWhenNotScanning() {
        // Given
        let session = ScanSession()

        // When
        session.pauseScanning()

        // Then
        XCTAssertEqual(session.state, .idle)
    }

    func testResumeScanning() {
        // Given
        let session = ScanSession()
        session.startScanning()
        session.pauseScanning()

        // When
        session.resumeScanning()

        // Then
        XCTAssertEqual(session.state, .scanning)
    }

    func testStopScanning() {
        // Given
        let session = ScanSession()
        session.startScanning()

        // When
        session.stopScanning()

        // Then
        XCTAssertEqual(session.state, .completed)
    }

    func testMarkProcessing() {
        // Given
        let session = ScanSession()

        // When
        session.markProcessing()

        // Then
        XCTAssertEqual(session.state, .processing)
    }

    func testMarkFailed() {
        // Given
        let session = ScanSession()

        // When
        session.markFailed()

        // Then
        XCTAssertEqual(session.state, .failed)
    }

    // MARK: - Data Management Tests

    func testAddMesh() {
        // Given
        let session = ScanSession()
        let mesh = createSampleMesh()

        // When
        session.addMesh(mesh)

        // Then
        XCTAssertEqual(session.combinedMesh.meshes.count, 1)
    }

    func testRemoveMesh() {
        // Given
        let session = ScanSession()
        let anchorId = UUID()
        let mesh = createSampleMesh(anchorId: anchorId)
        session.addMesh(mesh)

        // When
        session.removeMesh(identifier: anchorId)

        // Then
        XCTAssertEqual(session.combinedMesh.meshes.count, 0)
    }

    func testAddMeasurement() {
        // Given
        let session = ScanSession()
        let measurement = Measurement(
            type: .distance,
            points: [simd_float3(0, 0, 0), simd_float3(1, 0, 0)],
            value: 1.0
        )

        // When
        session.addMeasurement(measurement)

        // Then
        XCTAssertEqual(session.measurements.count, 1)
    }

    func testRemoveMeasurement() {
        // Given
        let session = ScanSession()
        let measurement = Measurement(
            type: .distance,
            points: [simd_float3(0, 0, 0), simd_float3(1, 0, 0)],
            value: 1.0
        )
        session.addMeasurement(measurement)

        // When
        session.removeMeasurement(measurement)

        // Then
        XCTAssertEqual(session.measurements.count, 0)
    }

    func testAddCameraPosition() {
        // Given
        let session = ScanSession()
        let transform = matrix_identity_float4x4

        // When
        session.addCameraPosition(transform)

        // Then
        XCTAssertEqual(session.deviceTrajectory.count, 1)
    }

    // MARK: - Computed Properties Tests

    func testVertexCount() {
        // Given
        let session = ScanSession()
        let mesh = createSampleMesh(vertexCount: 10)
        session.addMesh(mesh)

        // Then
        XCTAssertEqual(session.vertexCount, 10)
    }

    func testFaceCount() {
        // Given
        let session = ScanSession()
        let mesh = createSampleMesh(faceCount: 5)
        session.addMesh(mesh)

        // Then
        XCTAssertEqual(session.faceCount, 5)
    }

    func testFormattedDuration() {
        // Given
        let session = ScanSession()

        // Then
        XCTAssertFalse(session.formattedDuration.isEmpty)
    }

    // MARK: - Helper

    private func createSampleMesh(
        anchorId: UUID = UUID(),
        vertexCount: Int = 3,
        faceCount: Int = 1
    ) -> MeshData {
        let vertices = [simd_float3](repeating: simd_float3(0, 0, 0), count: vertexCount)
        let normals = [simd_float3](repeating: simd_float3(0, 0, 1), count: vertexCount)
        let faces = [simd_uint3](repeating: simd_uint3(0, 1, 2), count: faceCount)

        return MeshData(
            anchorIdentifier: anchorId,
            vertices: vertices,
            normals: normals,
            faces: faces
        )
    }
}

// MARK: - ScanState Tests

final class ScanStateTests: XCTestCase {

    func testAllStatesHaveDisplayNames() {
        let states: [ScanState] = [.idle, .scanning, .paused, .processing, .completed, .failed]

        for state in states {
            XCTAssertFalse(state.displayName.isEmpty)
        }
    }

    func testAllStatesHaveSystemImages() {
        let states: [ScanState] = [.idle, .scanning, .paused, .processing, .completed, .failed]

        for state in states {
            XCTAssertFalse(state.systemImage.isEmpty)
        }
    }
}

// MARK: - Measurement Tests

final class MeasurementTests: XCTestCase {

    func testDistanceMeasurement() {
        // Given/When
        let measurement = Measurement(
            type: .distance,
            points: [simd_float3(0, 0, 0), simd_float3(1, 0, 0)],
            value: 1.0,
            unit: .meters,
            label: "Test Distance"
        )

        // Then
        XCTAssertEqual(measurement.type, .distance)
        XCTAssertEqual(measurement.value, 1.0)
        XCTAssertEqual(measurement.unit, .meters)
        XCTAssertEqual(measurement.label, "Test Distance")
        XCTAssertEqual(measurement.points.count, 2)
    }

    func testFormattedValue() {
        // Given
        let measurement = Measurement(
            type: .distance,
            points: [simd_float3(0, 0, 0)],
            value: 1.5,
            unit: .meters
        )

        // Then
        XCTAssertEqual(measurement.formattedValue, "1.50 m")
    }

    func testFormattedValueInCentimeters() {
        // Given
        let measurement = Measurement(
            type: .distance,
            points: [simd_float3(0, 0, 0)],
            value: 1.5,  // meters
            unit: .centimeters
        )

        // Then
        XCTAssertEqual(measurement.formattedValue, "150.00 cm")
    }

    func testMeasurementTypes() {
        XCTAssertEqual(MeasurementType.distance.icon, "ruler")
        XCTAssertEqual(MeasurementType.area.icon, "square.dashed")
        XCTAssertEqual(MeasurementType.volume.icon, "cube")
        XCTAssertEqual(MeasurementType.angle.icon, "angle")
    }
}

// MARK: - MeasurementUnit Tests

final class MeasurementUnitTests: XCTestCase {

    func testSymbols() {
        XCTAssertEqual(MeasurementUnit.meters.symbol, "m")
        XCTAssertEqual(MeasurementUnit.centimeters.symbol, "cm")
        XCTAssertEqual(MeasurementUnit.feet.symbol, "ft")
        XCTAssertEqual(MeasurementUnit.inches.symbol, "in")
    }

    func testConversionMetersToMeters() {
        // Given
        let unit = MeasurementUnit.meters

        // When
        let result = unit.convert(1.0, from: .meters)

        // Then
        XCTAssertEqual(Double(result), 1.0, accuracy: 0.001)
    }

    func testConversionMetersToCentimeters() {
        // Given
        let unit = MeasurementUnit.centimeters

        // When
        let result = unit.convert(1.0, from: .meters)

        // Then
        XCTAssertEqual(Double(result), 100.0, accuracy: 0.001)
    }

    func testConversionMetersToFeet() {
        // Given
        let unit = MeasurementUnit.feet

        // When
        let result = unit.convert(1.0, from: .meters)

        // Then
        XCTAssertEqual(Double(result), 3.28084, accuracy: 0.001)
    }

    func testConversionMetersToInches() {
        // Given
        let unit = MeasurementUnit.inches

        // When
        let result = unit.convert(1.0, from: .meters)

        // Then
        XCTAssertEqual(Double(result), 39.3701, accuracy: 0.001)
    }

    func testConversionFeetToMeters() {
        // Given
        let unit = MeasurementUnit.meters

        // When
        let result = unit.convert(3.28084, from: .feet)

        // Then
        XCTAssertEqual(Double(result), 1.0, accuracy: 0.001)
    }

    func testConversionInchesToCentimeters() {
        // Given
        let unit = MeasurementUnit.centimeters

        // When
        let result = unit.convert(1.0, from: .inches)

        // Then
        XCTAssertEqual(Double(result), 2.54, accuracy: 0.001)
    }
}
