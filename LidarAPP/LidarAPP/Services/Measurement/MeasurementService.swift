import Foundation
import simd
import ARKit

/// Production measurement service for 3D space calculations.
/// Implements MeasurementServiceProtocol with full distance, area, and volume support.
@MainActor
@Observable
final class MeasurementService: MeasurementServiceProtocol {

    // MARK: - Properties

    /// History of completed measurements
    private(set) var measurements: [Measurement] = []

    /// Currently selected unit for display
    private(set) var selectedUnit: MeasurementUnit = .meters

    // MARK: - Initialization

    init() {
        debugLog("MeasurementService initialized", category: .logCategoryProcessing)
    }

    // MARK: - MeasurementServiceProtocol

    func measureDistance(from: simd_float3, to: simd_float3) -> MeasurementResult {
        let distance = DistanceCalculator.distance(from: from, to: to)
        debugLog(
            "Distance measured: \(String(format: "%.4f", distance))m between \(from) and \(to)",
            category: .logCategoryProcessing
        )
        return MeasurementResult(
            value: distance,
            unit: selectedUnit.symbol,
            startPoint: from,
            endPoint: to
        )
    }

    func calculateArea(points: [simd_float3]) -> Float {
        guard points.count >= 3 else {
            warningLog(
                "Cannot calculate area with \(points.count) points (minimum 3 required)",
                category: .logCategoryProcessing
            )
            return 0
        }
        let area = AreaCalculator.polygonArea(points: points)
        debugLog(
            "Area calculated: \(String(format: "%.4f", area)) m^2 from \(points.count) points",
            category: .logCategoryProcessing
        )
        return area
    }

    func calculateVolume(meshData: MeshData) -> Float {
        let volume = VolumeCalculator.meshVolume(meshData: meshData)
        debugLog(
            "Volume calculated: \(String(format: "%.4f", volume)) m^3 from \(meshData.faceCount) faces",
            category: .logCategoryProcessing
        )
        return volume
    }

    // MARK: - Additional Measurement Methods

    /// Calculate angle at a vertex between rays to two other points.
    /// Returns the angle in degrees.
    func measureAngle(vertex: simd_float3, point1: simd_float3, point2: simd_float3) -> Float {
        let v1 = point1 - vertex
        let v2 = point2 - vertex

        let len1 = simd_length(v1)
        let len2 = simd_length(v2)

        guard len1 > .ulpOfOne, len2 > .ulpOfOne else {
            warningLog("Cannot compute angle: degenerate vectors", category: .logCategoryProcessing)
            return 0
        }

        let cosAngle = simd_dot(v1, v2) / (len1 * len2)
        // Clamp to [-1, 1] to avoid NaN from floating point errors
        let clampedCos = max(-1.0, min(1.0, cosAngle))
        let angleRadians = acosf(clampedCos)
        let angleDegrees = angleRadians * 180.0 / .pi

        debugLog(
            "Angle measured: \(String(format: "%.2f", angleDegrees)) degrees at \(vertex)",
            category: .logCategoryProcessing
        )
        return angleDegrees
    }

    /// Measure vertical (Y-axis) distance between a ground point and a top point.
    /// In ARKit coordinate system, Y is up.
    func measureHeight(groundPoint: simd_float3, topPoint: simd_float3) -> Float {
        let height = abs(topPoint.y - groundPoint.y)
        debugLog(
            "Height measured: \(String(format: "%.4f", height))m",
            category: .logCategoryProcessing
        )
        return height
    }

    /// Set the preferred measurement unit for display
    func setUnit(_ unit: MeasurementUnit) {
        selectedUnit = unit
        debugLog("Measurement unit changed to \(unit.symbol)", category: .logCategoryProcessing)
    }

    // MARK: - Measurement Management

    /// Add a completed measurement to history
    func addMeasurement(_ measurement: Measurement) {
        measurements.append(measurement)
        debugLog(
            "Measurement added: \(measurement.type.rawValue) = \(measurement.formattedValue)",
            category: .logCategoryProcessing
        )
    }

    /// Remove a specific measurement from history
    func removeMeasurement(_ measurement: Measurement) {
        measurements.removeAll { $0.id == measurement.id }
        debugLog("Measurement removed: \(measurement.id)", category: .logCategoryProcessing)
    }

    /// Clear all measurements from history
    func clearMeasurements() {
        let count = measurements.count
        measurements.removeAll()
        debugLog("All measurements cleared (\(count) removed)", category: .logCategoryProcessing)
    }
}
