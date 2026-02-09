import Foundation
import simd

/// ViewModel for the interactive measurement UI.
/// Manages measurement mode, placed points, and communicates
/// with MeasurementService for calculations.
@MainActor
@Observable
final class MeasurementViewModel {

    // MARK: - Measurement Mode

    enum MeasurementMode: String, CaseIterable, Sendable {
        case distance
        case area
        case volume
        case angle

        var icon: String {
            switch self {
            case .distance: return "ruler"
            case .area: return "square.dashed"
            case .volume: return "cube"
            case .angle: return "angle"
            }
        }

        var label: String {
            switch self {
            case .distance: return "Vzdalenost"
            case .area: return "Plocha"
            case .volume: return "Objem"
            case .angle: return "Uhel"
            }
        }

        /// Minimum number of points required to complete this measurement type
        var minimumPoints: Int {
            switch self {
            case .distance: return 2
            case .area: return 3
            case .volume: return 1  // volume uses mesh data, point indicates selection
            case .angle: return 3   // vertex + 2 reference points
            }
        }

        /// Whether this mode allows adding more points beyond minimum
        var allowsMultiplePoints: Bool {
            switch self {
            case .distance: return false
            case .area: return true
            case .volume: return false
            case .angle: return false
            }
        }
    }

    // MARK: - State

    /// Currently active measurement mode
    var activeMode: MeasurementMode = .distance

    /// Points placed by the user in the current measurement
    var placedPoints: [simd_float3] = []

    /// Formatted result of the current/last measurement
    var currentResult: String = ""

    /// All saved measurements
    var measurements: [Measurement] = []

    /// Currently selected unit for display
    var selectedUnit: MeasurementUnit = .meters

    /// Whether the measurement list panel is visible
    var showMeasurementList: Bool = false

    /// Whether the user can complete the current measurement
    var canCompleteMeasurement: Bool {
        placedPoints.count >= activeMode.minimumPoints
    }

    /// Whether the user can undo the last point
    var canUndo: Bool {
        !placedPoints.isEmpty
    }

    /// Live distance string while placing points (for distance mode)
    var liveDistanceText: String {
        guard activeMode == .distance, placedPoints.count == 1 else { return "" }
        return "Umistate druhy bod"
    }

    /// Descriptive prompt for the user based on current state
    var instructionText: String {
        switch activeMode {
        case .distance:
            switch placedPoints.count {
            case 0: return "Klepnete pro umisteni prvniho bodu"
            case 1: return "Klepnete pro umisteni druheho bodu"
            default: return "Mereni dokonceno"
            }
        case .area:
            switch placedPoints.count {
            case 0: return "Klepnete pro umisteni bodu polygonu"
            case 1: return "Klepnete pro dalsi bod (min. 3)"
            case 2: return "Klepnete pro dalsi bod nebo dokoncete"
            default: return "Pridejte body nebo dokoncete mereni"
            }
        case .volume:
            return placedPoints.isEmpty
                ? "Klepnete na objekt pro vypocet objemu"
                : "Mereni objemu dokonceno"
        case .angle:
            switch placedPoints.count {
            case 0: return "Klepnete pro umisteni vrcholu uhlu"
            case 1: return "Klepnete pro prvni rameno"
            case 2: return "Klepnete pro druhe rameno"
            default: return "Mereni uhlu dokonceno"
            }
        }
    }

    // MARK: - Private

    private let services: ServiceContainer

    private var measurementService: any MeasurementServiceProtocol {
        services.measurement
    }

    // MARK: - Initialization

    init(services: ServiceContainer) {
        self.services = services
        debugLog("MeasurementViewModel initialized", category: .logCategoryUI)
    }

    // MARK: - Point Management

    /// Add a measurement point from an AR hit test result
    func addPoint(_ point: simd_float3) {
        placedPoints.append(point)
        debugLog(
            "Point added: \(point) (total: \(placedPoints.count))",
            category: .logCategoryUI
        )

        // Auto-complete for modes with exact point requirements
        switch activeMode {
        case .distance:
            if placedPoints.count == 2 {
                completeMeasurement()
            }
        case .angle:
            if placedPoints.count == 3 {
                completeMeasurement()
            }
        case .area, .volume:
            // Area requires explicit completion; volume is mesh-based
            break
        }
    }

    /// Complete the current measurement and save it
    func completeMeasurement() {
        guard canCompleteMeasurement else {
            warningLog(
                "Cannot complete measurement: need \(activeMode.minimumPoints) points, have \(placedPoints.count)",
                category: .logCategoryUI
            )
            return
        }

        let result = performMeasurement()
        guard let result else { return }

        let measurement = Measurement(
            type: result.type,
            points: placedPoints,
            value: result.value,
            unit: selectedUnit,
            label: result.label
        )

        measurements.append(measurement)
        currentResult = measurement.formattedValue

        // Forward to measurement service if it's the real implementation
        if let realService = measurementService as? MeasurementService {
            realService.addMeasurement(measurement)
        }

        debugLog(
            "Measurement completed: \(result.type.rawValue) = \(measurement.formattedValue)",
            category: .logCategoryUI
        )

        // Reset points for next measurement
        placedPoints.removeAll()
    }

    /// Undo the last placed point
    func undoLastPoint() {
        guard canUndo else { return }
        let removed = placedPoints.removeLast()
        currentResult = ""
        debugLog("Point undone: \(removed) (remaining: \(placedPoints.count))", category: .logCategoryUI)
    }

    /// Clear all placed points without saving
    func clearPoints() {
        placedPoints.removeAll()
        currentResult = ""
        debugLog("All points cleared", category: .logCategoryUI)
    }

    // MARK: - Measurement Management

    /// Delete a saved measurement
    func deleteMeasurement(_ measurement: Measurement) {
        measurements.removeAll { $0.id == measurement.id }

        if let realService = measurementService as? MeasurementService {
            realService.removeMeasurement(measurement)
        }

        debugLog("Measurement deleted: \(measurement.id)", category: .logCategoryUI)
    }

    /// Clear all saved measurements
    func clearAllMeasurements() {
        measurements.removeAll()

        if let realService = measurementService as? MeasurementService {
            realService.clearMeasurements()
        }

        currentResult = ""
        debugLog("All measurements cleared", category: .logCategoryUI)
    }

    // MARK: - Unit Management

    /// Change the display unit for measurements
    func changeUnit(_ unit: MeasurementUnit) {
        selectedUnit = unit

        if let realService = measurementService as? MeasurementService {
            realService.setUnit(unit)
        }

        debugLog("Unit changed to \(unit.symbol)", category: .logCategoryUI)
    }

    // MARK: - Mode Management

    /// Switch to a different measurement mode, clearing any in-progress points
    func switchMode(_ mode: MeasurementMode) {
        guard mode != activeMode else { return }
        clearPoints()
        activeMode = mode
        debugLog("Measurement mode switched to \(mode.rawValue)", category: .logCategoryUI)
    }

    // MARK: - Private Measurement Logic

    private struct MeasurementOutcome {
        let type: MeasurementType
        let value: Float
        let label: String?
    }

    private func performMeasurement() -> MeasurementOutcome? {
        switch activeMode {
        case .distance:
            return performDistanceMeasurement()
        case .area:
            return performAreaMeasurement()
        case .volume:
            return performVolumeMeasurement()
        case .angle:
            return performAngleMeasurement()
        }
    }

    private func performDistanceMeasurement() -> MeasurementOutcome? {
        guard placedPoints.count >= 2 else { return nil }

        let result = measurementService.measureDistance(
            from: placedPoints[0],
            to: placedPoints[1]
        )

        return MeasurementOutcome(
            type: .distance,
            value: result.value,
            label: nil
        )
    }

    private func performAreaMeasurement() -> MeasurementOutcome? {
        guard placedPoints.count >= 3 else { return nil }

        let area = measurementService.calculateArea(points: placedPoints)

        return MeasurementOutcome(
            type: .area,
            value: area,
            label: nil
        )
    }

    private func performVolumeMeasurement() -> MeasurementOutcome? {
        // Volume measurement uses the mesh from the AR session
        // For now, create a basic bounding box volume from placed points
        guard !placedPoints.isEmpty else { return nil }

        let volume = VolumeCalculator.boundingBoxVolume(points: placedPoints)

        return MeasurementOutcome(
            type: .volume,
            value: volume,
            label: nil
        )
    }

    private func performAngleMeasurement() -> MeasurementOutcome? {
        guard placedPoints.count >= 3 else { return nil }

        // placedPoints[0] is the vertex, [1] and [2] are the two rays
        guard let realService = measurementService as? MeasurementService else {
            // Fallback angle calculation
            let v1 = placedPoints[1] - placedPoints[0]
            let v2 = placedPoints[2] - placedPoints[0]
            let len1 = simd_length(v1)
            let len2 = simd_length(v2)
            guard len1 > .ulpOfOne, len2 > .ulpOfOne else { return nil }
            let cosAngle = simd_dot(v1, v2) / (len1 * len2)
            let clampedCos = max(-1.0, min(1.0, cosAngle))
            let angleDegrees = acosf(clampedCos) * 180.0 / .pi

            return MeasurementOutcome(
                type: .angle,
                value: angleDegrees,
                label: nil
            )
        }

        let angle = realService.measureAngle(
            vertex: placedPoints[0],
            point1: placedPoints[1],
            point2: placedPoints[2]
        )

        return MeasurementOutcome(
            type: .angle,
            value: angle,
            label: nil
        )
    }
}
