import Foundation
import simd
import ARKit

/// Main service orchestrating all measurement operations
@MainActor
@Observable
final class MeasurementService {

    // MARK: - Measurement Mode

    enum MeasurementMode: String, CaseIterable {
        case distance = "Distance"
        case area = "Area"
        case volume = "Volume"
        case angle = "Angle"

        var icon: String {
            switch self {
            case .distance: return "ruler"
            case .area: return "square.dashed"
            case .volume: return "cube"
            case .angle: return "angle"
            }
        }

        var description: String {
            switch self {
            case .distance: return "Measure point-to-point distance"
            case .area: return "Measure surface area"
            case .volume: return "Measure volume of enclosed space"
            case .angle: return "Measure angle between surfaces"
            }
        }
    }

    // MARK: - Unit System

    enum UnitSystem: String, CaseIterable {
        case metric = "Metric"
        case imperial = "Imperial"

        var lengthUnit: LengthUnit {
            switch self {
            case .metric: return .meters
            case .imperial: return .feet
            }
        }

        var areaUnit: AreaUnit {
            switch self {
            case .metric: return .squareMeters
            case .imperial: return .squareFeet
            }
        }

        var volumeUnit: VolumeUnit {
            switch self {
            case .metric: return .cubicMeters
            case .imperial: return .cubicFeet
            }
        }
    }

    enum LengthUnit: String {
        case meters = "m"
        case centimeters = "cm"
        case millimeters = "mm"
        case feet = "ft"
        case inches = "in"

        func convert(fromMeters value: Float) -> Float {
            switch self {
            case .meters: return value
            case .centimeters: return value * 100
            case .millimeters: return value * 1000
            case .feet: return value * 3.28084
            case .inches: return value * 39.3701
            }
        }

        func format(_ value: Float) -> String {
            let converted = convert(fromMeters: value)
            switch self {
            case .millimeters: return String(format: "%.0f %@", converted, rawValue)
            case .centimeters: return String(format: "%.1f %@", converted, rawValue)
            default: return String(format: "%.2f %@", converted, rawValue)
            }
        }
    }

    enum AreaUnit: String {
        case squareMeters = "m²"
        case squareCentimeters = "cm²"
        case squareFeet = "ft²"
        case squareInches = "in²"

        func convert(fromSquareMeters value: Float) -> Float {
            switch self {
            case .squareMeters: return value
            case .squareCentimeters: return value * 10000
            case .squareFeet: return value * 10.7639
            case .squareInches: return value * 1550.0
            }
        }

        func format(_ value: Float) -> String {
            let converted = convert(fromSquareMeters: value)
            return String(format: "%.2f %@", converted, rawValue)
        }
    }

    enum VolumeUnit: String {
        case cubicMeters = "m³"
        case liters = "L"
        case cubicFeet = "ft³"
        case gallons = "gal"

        func convert(fromCubicMeters value: Float) -> Float {
            switch self {
            case .cubicMeters: return value
            case .liters: return value * 1000
            case .cubicFeet: return value * 35.3147
            case .gallons: return value * 264.172
            }
        }

        func format(_ value: Float) -> String {
            let converted = convert(fromCubicMeters: value)
            return String(format: "%.2f %@", converted, rawValue)
        }
    }

    // MARK: - Measurement Result

    struct MeasurementResult: Identifiable, Sendable {
        let id: UUID
        let type: MeasurementMode
        let value: Float
        let formattedValue: String
        let points: [simd_float3]
        let timestamp: Date
        let confidence: Float
        let metadata: [String: String]

        init(
            id: UUID = UUID(),
            type: MeasurementMode,
            value: Float,
            formattedValue: String,
            points: [simd_float3],
            confidence: Float = 1.0,
            metadata: [String: String] = [:]
        ) {
            self.id = id
            self.type = type
            self.value = value
            self.formattedValue = formattedValue
            self.points = points
            self.timestamp = Date()
            self.confidence = confidence
            self.metadata = metadata
        }
    }

    // MARK: - Properties

    private(set) var currentMode: MeasurementMode = .distance
    private(set) var unitSystem: UnitSystem = .metric
    private(set) var measurements: [MeasurementResult] = []
    private(set) var currentPoints: [simd_float3] = []

    private let distanceCalculator = DistanceCalculator()
    private let areaCalculator = AreaCalculator()
    private let volumeCalculator = VolumeCalculator()

    // Current mesh data for raycasting
    private var meshData: MeshData?

    // MARK: - Initialization

    init() {}

    // MARK: - Mode Control

    func setMode(_ mode: MeasurementMode) {
        currentMode = mode
        clearCurrentPoints()
    }

    func setUnitSystem(_ system: UnitSystem) {
        unitSystem = system
    }

    func setMeshData(_ mesh: MeshData) {
        self.meshData = mesh
    }

    // MARK: - Point Management

    func addPoint(_ point: simd_float3) {
        currentPoints.append(point)

        // Auto-complete certain measurements
        switch currentMode {
        case .distance:
            if currentPoints.count == 2 {
                completeMeasurement()
            }
        case .angle:
            if currentPoints.count == 3 {
                completeMeasurement()
            }
        default:
            break  // Area and volume need manual completion
        }
    }

    func removeLastPoint() {
        if !currentPoints.isEmpty {
            currentPoints.removeLast()
        }
    }

    func clearCurrentPoints() {
        currentPoints.removeAll()
    }

    // MARK: - Measurement Execution

    func completeMeasurement() {
        guard !currentPoints.isEmpty else { return }

        var result: MeasurementResult?

        switch currentMode {
        case .distance:
            result = measureDistance()
        case .area:
            result = measureArea()
        case .volume:
            result = measureVolume()
        case .angle:
            result = measureAngle()
        }

        if let measurement = result {
            measurements.append(measurement)
        }

        clearCurrentPoints()
    }

    // MARK: - Distance Measurement

    private func measureDistance() -> MeasurementResult? {
        guard currentPoints.count >= 2 else { return nil }

        if currentPoints.count == 2 {
            // Simple point-to-point
            let distance = distanceCalculator.pointToPointDistance(
                from: currentPoints[0],
                to: currentPoints[1]
            )

            return MeasurementResult(
                type: .distance,
                value: distance,
                formattedValue: unitSystem.lengthUnit.format(distance),
                points: currentPoints,
                confidence: 1.0
            )
        } else {
            // Polyline measurement
            let totalDistance = distanceCalculator.polylineDistance(points: currentPoints)

            return MeasurementResult(
                type: .distance,
                value: totalDistance,
                formattedValue: unitSystem.lengthUnit.format(totalDistance),
                points: currentPoints,
                confidence: 1.0,
                metadata: ["segments": "\(currentPoints.count - 1)"]
            )
        }
    }

    // MARK: - Area Measurement

    private func measureArea() -> MeasurementResult? {
        guard currentPoints.count >= 3 else { return nil }

        let area = areaCalculator.polygonArea(vertices: currentPoints)

        return MeasurementResult(
            type: .area,
            value: area,
            formattedValue: unitSystem.areaUnit.format(area),
            points: currentPoints,
            confidence: 1.0,
            metadata: ["vertices": "\(currentPoints.count)"]
        )
    }

    // MARK: - Volume Measurement

    private func measureVolume() -> MeasurementResult? {
        // For volume, we need either:
        // 1. A closed mesh region
        // 2. A bounding box defined by points
        // 3. A floor polygon + height

        guard currentPoints.count >= 4 else { return nil }

        // Simple approach: compute bounding box volume
        let volume = volumeCalculator.boundingBoxVolume(points: currentPoints)

        return MeasurementResult(
            type: .volume,
            value: volume,
            formattedValue: unitSystem.volumeUnit.format(volume),
            points: currentPoints,
            confidence: 0.8,
            metadata: ["method": "bounding_box"]
        )
    }

    // MARK: - Angle Measurement

    private func measureAngle() -> MeasurementResult? {
        guard currentPoints.count >= 3 else { return nil }

        let angle = distanceCalculator.angleBetweenVectors(
            vertex: currentPoints[1],
            point1: currentPoints[0],
            point2: currentPoints[2]
        )

        let degrees = angle * 180 / .pi

        return MeasurementResult(
            type: .angle,
            value: degrees,
            formattedValue: String(format: "%.1f°", degrees),
            points: currentPoints,
            confidence: 1.0
        )
    }

    // MARK: - Raycast to Mesh

    /// Find intersection point with mesh from screen coordinates
    func raycastToMesh(
        origin: simd_float3,
        direction: simd_float3
    ) -> simd_float3? {
        guard let mesh = meshData else { return nil }

        return distanceCalculator.rayMeshIntersection(
            origin: origin,
            direction: direction,
            mesh: mesh
        )
    }

    // MARK: - Measurement Management

    func deleteMeasurement(_ id: UUID) {
        measurements.removeAll { $0.id == id }
    }

    func clearAllMeasurements() {
        measurements.removeAll()
    }

    func exportMeasurements() -> Data? {
        let exportData = measurements.map { measurement -> [String: Any] in
            [
                "id": measurement.id.uuidString,
                "type": measurement.type.rawValue,
                "value": measurement.value,
                "formattedValue": measurement.formattedValue,
                "points": measurement.points.map { [$0.x, $0.y, $0.z] },
                "timestamp": ISO8601DateFormatter().string(from: measurement.timestamp),
                "confidence": measurement.confidence,
                "metadata": measurement.metadata
            ]
        }

        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    // MARK: - Real-time Preview

    /// Get preview distance while user is placing second point
    func previewDistance(to point: simd_float3) -> Float? {
        guard currentMode == .distance,
              let firstPoint = currentPoints.first else {
            return nil
        }

        return distanceCalculator.pointToPointDistance(from: firstPoint, to: point)
    }

    /// Get preview area while user is defining polygon
    func previewArea(with point: simd_float3) -> Float? {
        guard currentMode == .area, currentPoints.count >= 2 else {
            return nil
        }

        var previewPoints = currentPoints
        previewPoints.append(point)

        return areaCalculator.polygonArea(vertices: previewPoints)
    }
}

// MARK: - Statistics

extension MeasurementService {

    struct MeasurementStatistics {
        let totalMeasurements: Int
        let measurementsByType: [MeasurementMode: Int]
        let averageConfidence: Float
        let totalDistance: Float
        let totalArea: Float
        let totalVolume: Float
    }

    var statistics: MeasurementStatistics {
        var byType: [MeasurementMode: Int] = [:]
        var totalDistance: Float = 0
        var totalArea: Float = 0
        var totalVolume: Float = 0
        var totalConfidence: Float = 0

        for measurement in measurements {
            byType[measurement.type, default: 0] += 1
            totalConfidence += measurement.confidence

            switch measurement.type {
            case .distance:
                totalDistance += measurement.value
            case .area:
                totalArea += measurement.value
            case .volume:
                totalVolume += measurement.value
            case .angle:
                break
            }
        }

        return MeasurementStatistics(
            totalMeasurements: measurements.count,
            measurementsByType: byType,
            averageConfidence: measurements.isEmpty ? 0 : totalConfidence / Float(measurements.count),
            totalDistance: totalDistance,
            totalArea: totalArea,
            totalVolume: totalVolume
        )
    }
}
