import ARKit
import AVFoundation
import Darwin
import CoreML

/// Utility for checking device capabilities required for LiDAR scanning
enum DeviceCapabilities {

    // MARK: - Neural Engine

    /// Check if device has Neural Engine (A11 Bionic or later)
    static var hasNeuralEngine: Bool {
        // All devices with LiDAR have Neural Engine
        // iPhone 12 Pro+ and iPad Pro 2020+ have A14/M1 or later
        if #available(iOS 15.0, *) {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            return true
        }
        return false
    }

    // MARK: - Memory Monitoring

    /// Available memory in megabytes
    static var availableMemoryMB: Int {
        Int(os_proc_available_memory() / 1_000_000)
    }

    /// Total physical memory in megabytes
    static var totalMemoryMB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_000_000)
    }

    /// Current memory pressure level
    static var memoryPressureLevel: MemoryPressureLevel {
        let available = availableMemoryMB
        switch available {
        case 0..<100:
            return .critical
        case 100..<300:
            return .warning
        default:
            return .normal
        }
    }

    /// Check if device has sufficient memory for large scan
    static var hasSufficientMemoryForLargeScan: Bool {
        availableMemoryMB > 500
    }

    /// Recommended max points based on available memory
    static var recommendedMaxPoints: Int {
        let available = availableMemoryMB
        switch available {
        case 0..<200:
            return 100_000
        case 200..<500:
            return 300_000
        case 500..<1000:
            return 500_000
        default:
            return 1_000_000
        }
    }

    /// Check if device has LiDAR sensor
    static var hasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// Check if device supports depth capture
    static var supportsDepthCapture: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// Check if device supports 4K video capture
    static var supports4KVideo: Bool {
        ARWorldTrackingConfiguration.recommendedVideoFormatFor4KResolution != nil
    }

    /// Check if all minimum requirements are met
    static var minimumRequirementsMet: Bool {
        hasLiDAR && supportsDepthCapture
    }

    /// Perform comprehensive capability check
    static func checkCapabilities() -> CapabilityCheckResult {
        var issues: [CapabilityIssue] = []

        if !ARWorldTrackingConfiguration.isSupported {
            issues.append(.arNotSupported)
        }

        if !hasLiDAR {
            issues.append(.noLiDAR)
        }

        if !supportsDepthCapture {
            issues.append(.noDepthCapture)
        }

        if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
            issues.append(.cameraPermissionDenied)
        }

        return CapabilityCheckResult(issues: issues)
    }

    /// Request camera permission
    static func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

// MARK: - Supporting Types

/// Memory pressure levels for adaptive scanning
enum MemoryPressureLevel: String, Sendable {
    case normal
    case warning
    case critical

    var description: String {
        switch self {
        case .normal:
            return "Memory OK"
        case .warning:
            return "Low memory - reducing quality"
        case .critical:
            return "Critical memory - saving to disk"
        }
    }

    /// Recommended action for this pressure level
    var recommendedAction: MemoryAction {
        switch self {
        case .normal:
            return .none
        case .warning:
            return .reduceQuality
        case .critical:
            return .flushToDisk
        }
    }
}

enum MemoryAction: Sendable {
    case none
    case reduceQuality
    case flushToDisk
}

struct CapabilityCheckResult {
    let issues: [CapabilityIssue]

    var isCapable: Bool { issues.isEmpty }
    var hasLiDARIssue: Bool { issues.contains(.noLiDAR) }
    var hasCameraIssue: Bool { issues.contains(.cameraPermissionDenied) }

    var primaryIssue: CapabilityIssue? { issues.first }
}

enum CapabilityIssue: String, CaseIterable {
    case arNotSupported
    case noLiDAR
    case noDepthCapture
    case cameraPermissionDenied

    var title: String {
        switch self {
        case .arNotSupported:
            return "AR Not Supported"
        case .noLiDAR:
            return "LiDAR Required"
        case .noDepthCapture:
            return "Depth Capture Required"
        case .cameraPermissionDenied:
            return "Camera Access Required"
        }
    }

    var message: String {
        switch self {
        case .arNotSupported:
            return "This device does not support AR experiences."
        case .noLiDAR:
            return "This app requires a LiDAR-equipped device (iPhone 12 Pro or later, iPad Pro 2020 or later)."
        case .noDepthCapture:
            return "Depth capture is not supported on this device."
        case .cameraPermissionDenied:
            return "Camera access is required. Please enable it in Settings."
        }
    }

    var systemImage: String {
        switch self {
        case .arNotSupported:
            return "arkit"
        case .noLiDAR:
            return "sensor.tag.radiowaves.forward"
        case .noDepthCapture:
            return "camera.aperture"
        case .cameraPermissionDenied:
            return "camera.fill"
        }
    }
}
