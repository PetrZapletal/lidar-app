import Foundation
import ARKit
import RealityKit
import SwiftUI

// MARK: - App Diagnostics Service

/// In-app diagnostics and testing framework
@MainActor
@Observable
final class AppDiagnostics {
    static let shared = AppDiagnostics()

    // MARK: - Test Results

    var testResults: [DiagnosticTest] = []
    var isRunning = false
    var lastRunDate: Date?

    // MARK: - Device Info

    struct DeviceInfo {
        let hasLiDAR: Bool
        let supportsSceneReconstruction: Bool
        let supportsDepthCapture: Bool
        let deviceModel: String
        let osVersion: String
        let totalMemory: UInt64
    }

    var deviceInfo: DeviceInfo {
        DeviceInfo(
            hasLiDAR: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            supportsSceneReconstruction: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            supportsDepthCapture: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            deviceModel: UIDevice.current.modelIdentifier,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            totalMemory: ProcessInfo.processInfo.physicalMemory
        )
    }

    // MARK: - Run All Tests

    func runAllTests() async {
        isRunning = true
        testResults.removeAll()

        await runTest("Device LiDAR Check") {
            ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }

        await runTest("Scene Reconstruction Support") {
            ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }

        await runTest("Depth Capture Support") {
            ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        }

        await runTest("Documents Directory Access") {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            return docs != nil && FileManager.default.fileExists(atPath: docs!.path)
        }

        await runTest("Write Test File") {
            do {
                let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostic_test.txt")
                try "test".write(to: testURL, atomically: true, encoding: .utf8)
                try FileManager.default.removeItem(at: testURL)
                return true
            } catch {
                return false
            }
        }

        await runTest("AR Session Creation") {
            ARWorldTrackingConfiguration.isSupported
        }

        await runTest("Memory Available (>500MB)") {
            ProcessInfo.processInfo.physicalMemory > 500_000_000
        }

        lastRunDate = Date()
        isRunning = false
    }

    private func runTest(_ name: String, test: @escaping () -> Bool) async {
        let startTime = Date()
        let passed = test()
        let duration = Date().timeIntervalSince(startTime)

        testResults.append(DiagnosticTest(
            name: name,
            passed: passed,
            duration: duration,
            timestamp: Date()
        ))
    }

    // MARK: - Export Report

    func exportReport() -> String {
        var report = """
        ========================================
        LiDAR Scanner Diagnostic Report
        Generated: \(Date().formatted())
        ========================================

        DEVICE INFO:
        - Model: \(deviceInfo.deviceModel)
        - OS: \(deviceInfo.osVersion)
        - LiDAR: \(deviceInfo.hasLiDAR ? "YES" : "NO")
        - Scene Reconstruction: \(deviceInfo.supportsSceneReconstruction ? "YES" : "NO")
        - Depth Capture: \(deviceInfo.supportsDepthCapture ? "YES" : "NO")
        - Memory: \(ByteCountFormatter.string(fromByteCount: Int64(deviceInfo.totalMemory), countStyle: .memory))

        TEST RESULTS:
        """

        for test in testResults {
            let status = test.passed ? "PASS" : "FAIL"
            report += "\n[\(status)] \(test.name) (\(String(format: "%.2fms", test.duration * 1000)))"
        }

        report += "\n\n========================================"
        return report
    }
}

// MARK: - Diagnostic Test Model

struct DiagnosticTest: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let duration: TimeInterval
    let timestamp: Date
}
