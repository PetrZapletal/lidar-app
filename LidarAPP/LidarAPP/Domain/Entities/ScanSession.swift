import Foundation
import simd
import UIKit

/// Represents a complete scanning session with all captured data
@Observable
final class ScanSession: Identifiable, @unchecked Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    private(set) var updatedAt: Date
    private(set) var state: ScanState

    // MARK: - Memory Management Constants (Performance Optimization)
    /// Maximum number of texture frames to keep in memory
    private static let maxTextureFramesInMemory = 50
    /// Maximum number of depth frames to keep in memory
    private static let maxDepthFramesInMemory = 50
    /// Number of most recent frames to retain after cleanup
    private static let framesRetainedAfterCleanup = 10
    /// Maximum trajectory points before pruning (keep every Nth point)
    private static let maxTrajectoryPoints = 500

    // Scan data
    var pointCloud: PointCloud?
    let combinedMesh: CombinedMesh
    private(set) var textureFrames: [TextureFrame]
    private(set) var depthFrames: [DepthFrame] = []
    private(set) var measurements: [Measurement]

    // Statistics
    private(set) var scanDuration: TimeInterval
    private(set) var deviceTrajectory: [simd_float4x4]
    private var scanStartTime: Date?

    /// Count of total texture frames captured (including flushed ones)
    private(set) var totalTextureFramesCaptured: Int = 0
    /// Count of total depth frames captured (including flushed ones)
    private(set) var totalDepthFramesCaptured: Int = 0

    // Device info
    let deviceModel: String
    let appVersion: String
    var notes: String

    init(
        id: UUID = UUID(),
        name: String = "New Scan"
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.state = .idle
        self.combinedMesh = CombinedMesh()
        self.textureFrames = []
        self.measurements = []
        self.scanDuration = 0
        self.deviceTrajectory = []
        self.deviceModel = UIDevice.current.modelIdentifier
        self.appVersion = Bundle.main.appVersion
        self.notes = ""
    }

    // MARK: - State Management

    func startScanning() {
        guard state == .idle || state == .paused else { return }
        state = .scanning
        scanStartTime = Date()
    }

    func pauseScanning() {
        guard state == .scanning else { return }
        state = .paused
        updateDuration()
    }

    func resumeScanning() {
        guard state == .paused else { return }
        state = .scanning
        scanStartTime = Date()
    }

    func stopScanning() {
        state = .completed
        updateDuration()
        updatedAt = Date()
    }

    func markProcessing() {
        state = .processing
    }

    func markFailed() {
        state = .failed
    }

    /// Reset all scan data for a fresh start
    func reset() {
        state = .idle
        pointCloud = nil
        combinedMesh.clear()
        textureFrames = []
        depthFrames = []
        measurements = []
        scanDuration = 0
        deviceTrajectory = []
        scanStartTime = nil
        totalTextureFramesCaptured = 0
        totalDepthFramesCaptured = 0
        updatedAt = Date()
    }

    private func updateDuration() {
        if let startTime = scanStartTime {
            scanDuration += Date().timeIntervalSince(startTime)
            scanStartTime = nil
        }
    }

    // MARK: - Data Management

    func addMesh(_ mesh: MeshData) {
        combinedMesh.addOrUpdate(mesh)
        updatedAt = Date()
    }

    func removeMesh(identifier: UUID) {
        combinedMesh.remove(identifier: identifier)
        updatedAt = Date()
    }

    func addTextureFrame(_ frame: TextureFrame) {
        textureFrames.append(frame)
        totalTextureFramesCaptured += 1

        // PERFORMANCE: Enforce memory limit - flush older frames when limit exceeded
        if textureFrames.count > Self.maxTextureFramesInMemory {
            // Keep only the most recent frames
            let startIndex = textureFrames.count - Self.framesRetainedAfterCleanup
            textureFrames = Array(textureFrames[startIndex...])
        }

        updatedAt = Date()
    }

    func addDepthFrame(_ frame: DepthFrame) {
        depthFrames.append(frame)
        totalDepthFramesCaptured += 1

        // PERFORMANCE: Enforce memory limit - flush older frames when limit exceeded
        if depthFrames.count > Self.maxDepthFramesInMemory {
            // Keep only the most recent frames
            let startIndex = depthFrames.count - Self.framesRetainedAfterCleanup
            depthFrames = Array(depthFrames[startIndex...])
        }

        updatedAt = Date()
    }

    func addCameraPosition(_ transform: simd_float4x4) {
        deviceTrajectory.append(transform)

        // PERFORMANCE: Prune trajectory to avoid unbounded memory growth
        // Keep every Nth point when exceeding max
        if deviceTrajectory.count > Self.maxTrajectoryPoints * 2 {
            // Downsample: keep every other point
            deviceTrajectory = deviceTrajectory.enumerated()
                .filter { $0.offset % 2 == 0 }
                .map { $0.element }
        }
    }

    func addMeasurement(_ measurement: Measurement) {
        measurements.append(measurement)
        updatedAt = Date()
    }

    func removeMeasurement(_ measurement: Measurement) {
        measurements.removeAll { $0.id == measurement.id }
        updatedAt = Date()
    }

    // MARK: - Computed Properties

    var areaScanned: Float {
        combinedMesh.totalSurfaceArea
    }

    var vertexCount: Int {
        combinedMesh.totalVertexCount
    }

    var faceCount: Int {
        combinedMesh.totalFaceCount
    }

    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: scanDuration) ?? "0s"
    }
}

// MARK: - Supporting Types

enum ScanState: String, Sendable {
    case idle
    case scanning
    case paused
    case processing
    case completed
    case failed

    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .scanning: return "Scanning"
        case .paused: return "Paused"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "circle"
        case .scanning: return "record.circle"
        case .paused: return "pause.circle"
        case .processing: return "gearshape.2"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }
}

/// Represents a captured camera frame with metadata
struct TextureFrame: Identifiable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    let imageData: Data
    let resolution: CGSize
    let intrinsics: simd_float3x3
    let cameraTransform: simd_float4x4
    let exposureDuration: TimeInterval?
    let iso: Float?

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        imageData: Data,
        resolution: CGSize,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        exposureDuration: TimeInterval? = nil,
        iso: Float? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.imageData = imageData
        self.resolution = resolution
        self.intrinsics = intrinsics
        self.cameraTransform = cameraTransform
        self.exposureDuration = exposureDuration
        self.iso = iso
    }
}

/// Represents a measurement in the scanned environment
struct Measurement: Identifiable, Sendable {
    let id: UUID
    let type: MeasurementType
    let points: [simd_float3]
    let value: Float
    let unit: MeasurementUnit
    let label: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        type: MeasurementType,
        points: [simd_float3],
        value: Float,
        unit: MeasurementUnit = .meters,
        label: String? = nil
    ) {
        self.id = id
        self.type = type
        self.points = points
        self.value = value
        self.unit = unit
        self.label = label
        self.createdAt = Date()
    }

    var formattedValue: String {
        let converted = unit.convert(value, from: .meters)
        return String(format: "%.2f %@", converted, unit.symbol)
    }
}

enum MeasurementType: String, Sendable {
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
}

enum MeasurementUnit: String, Codable, CaseIterable, Sendable {
    case meters
    case centimeters
    case feet
    case inches

    var symbol: String {
        switch self {
        case .meters: return "m"
        case .centimeters: return "cm"
        case .feet: return "ft"
        case .inches: return "in"
        }
    }

    func convert(_ value: Float, from: MeasurementUnit) -> Float {
        // Convert to meters first
        let inMeters: Float
        switch from {
        case .meters: inMeters = value
        case .centimeters: inMeters = value / 100
        case .feet: inMeters = value * 0.3048
        case .inches: inMeters = value * 0.0254
        }

        // Convert from meters to target unit
        switch self {
        case .meters: return inMeters
        case .centimeters: return inMeters * 100
        case .feet: return inMeters / 0.3048
        case .inches: return inMeters / 0.0254
        }
    }
}

// MARK: - Extensions

extension UIDevice {
    var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
