import ARKit
import AVFoundation

/// Utility for checking device capabilities required for LiDAR scanning
enum DeviceCapabilities {

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
