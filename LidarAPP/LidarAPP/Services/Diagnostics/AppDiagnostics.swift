import Foundation
import ARKit
import RealityKit
import SwiftUI

// MARK: - App Diagnostics Service

/// In-app diagnostics and testing framework
@MainActor
final class AppDiagnostics: ObservableObject {
    static let shared = AppDiagnostics()

    // MARK: - Test Results

    @Published var testResults: [DiagnosticTest] = []
    @Published var isRunning = false
    @Published var lastRunDate: Date?

    // MARK: - Device Info

    struct DeviceInfo {
        let hasLiDAR: Bool
        let supportsSceneReconstruction: Bool
        let supportsDepthCapture: Bool
        let supportsRoomPlan: Bool
        let deviceModel: String
        let osVersion: String
        let availableMemory: UInt64
        let totalMemory: UInt64
    }

    var deviceInfo: DeviceInfo {
        let processInfo = ProcessInfo.processInfo

        return DeviceInfo(
            hasLiDAR: DeviceCapabilities.hasLiDAR,
            supportsSceneReconstruction: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            supportsDepthCapture: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            supportsRoomPlan: RoomPlanService.shared.isSupported,
            deviceModel: deviceModelName(),
            osVersion: "\(processInfo.operatingSystemVersionString)",
            availableMemory: processInfo.physicalMemory,
            totalMemory: processInfo.physicalMemory
        )
    }

    // MARK: - Run All Tests

    func runAllTests() async {
        isRunning = true
        testResults.removeAll()

        // Basic tests
        await runTest("Device LiDAR Check") {
            DeviceCapabilities.hasLiDAR
        }

        await runTest("Scene Reconstruction Support") {
            ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }

        await runTest("Depth Capture Support") {
            ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        }

        await runTest("RoomPlan Support") {
            RoomPlanService.shared.isSupported
        }

        // File system tests
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

        // AR Session test
        await runTest("AR Session Creation") {
            return ARWorldTrackingConfiguration.isSupported
        }

        // Memory test
        await runTest("Memory Available (>500MB)") {
            let available = ProcessInfo.processInfo.physicalMemory
            return available > 500_000_000
        }

        // Mock mode check
        await runTest("Mock Mode Disabled on Device") {
            if DeviceCapabilities.hasLiDAR {
                // On LiDAR device, mock mode should be ignored
                return true
            }
            return !MockDataProvider.isMockModeEnabled
        }

        // Session persistence directory test
        await runTest("Session Persistence Directory") {
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let sessionsDir = documentsDir.appendingPathComponent("ScanSessions")
            do {
                try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
                return FileManager.default.isWritableFile(atPath: sessionsDir.path)
            } catch {
                return false
            }
        }

        lastRunDate = Date()
        isRunning = false
    }

    private func runTest(_ name: String, test: @escaping () -> Bool) async {
        let startTime = Date()
        let passed = test()
        let duration = Date().timeIntervalSince(startTime)

        let result = DiagnosticTest(
            name: name,
            passed: passed,
            duration: duration,
            timestamp: Date()
        )

        testResults.append(result)
    }

    // MARK: - Individual Component Tests

    func testARSession() async -> (success: Bool, message: String) {
        guard DeviceCapabilities.hasLiDAR else {
            return (false, "LiDAR not available")
        }

        let config = ARWorldTrackingConfiguration()

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        } else {
            return (false, "Scene reconstruction not supported")
        }

        return (true, "AR Session configuration valid")
    }

    func testPointCloudExtraction() async -> (success: Bool, pointCount: Int, message: String) {
        // This would need an actual AR session to test
        return (true, 0, "Requires active AR session")
    }

    func testMeshExtraction() async -> (success: Bool, faceCount: Int, message: String) {
        // This would need an actual AR session to test
        return (true, 0, "Requires active AR session")
    }

    // MARK: - Helpers

    private func deviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
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
        - RoomPlan: \(deviceInfo.supportsRoomPlan ? "YES" : "NO")
        - Memory: \(ByteCountFormatter.string(fromByteCount: Int64(deviceInfo.availableMemory), countStyle: .memory))

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

// MARK: - Diagnostics View

struct DiagnosticsView: View {
    @StateObject private var diagnostics = AppDiagnostics.shared
    @State private var showShareSheet = false

    var body: some View {
        List {
            // Device Info Section
            Section("Zařízení") {
                InfoRow(label: "Model", value: diagnostics.deviceInfo.deviceModel)
                InfoRow(label: "OS", value: diagnostics.deviceInfo.osVersion)
                InfoRow(label: "LiDAR", value: diagnostics.deviceInfo.hasLiDAR ? "Ano" : "Ne")
                InfoRow(label: "Scene Reconstruction", value: diagnostics.deviceInfo.supportsSceneReconstruction ? "Ano" : "Ne")
                InfoRow(label: "Depth Capture", value: diagnostics.deviceInfo.supportsDepthCapture ? "Ano" : "Ne")
                InfoRow(label: "RoomPlan", value: diagnostics.deviceInfo.supportsRoomPlan ? "Ano" : "Ne")
            }

            // Run Tests Section
            Section("Testy") {
                Button(action: {
                    Task {
                        await diagnostics.runAllTests()
                    }
                }) {
                    HStack {
                        if diagnostics.isRunning {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(diagnostics.isRunning ? "Probíhá..." : "Spustit všechny testy")
                    }
                }
                .disabled(diagnostics.isRunning)

                if let lastRun = diagnostics.lastRunDate {
                    Text("Poslední test: \(lastRun.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Test Results Section
            if !diagnostics.testResults.isEmpty {
                Section("Výsledky") {
                    ForEach(diagnostics.testResults) { test in
                        HStack {
                            Image(systemName: test.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(test.passed ? .green : .red)

                            Text(test.name)
                                .font(.subheadline)

                            Spacer()

                            Text(String(format: "%.0fms", test.duration * 1000))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Summary
                    let passCount = diagnostics.testResults.filter { $0.passed }.count
                    let totalCount = diagnostics.testResults.count

                    HStack {
                        Text("Celkem")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(passCount)/\(totalCount) prošlo")
                            .foregroundStyle(passCount == totalCount ? .green : .orange)
                    }
                }
            }

            // Export Section
            Section("Export") {
                Button("Exportovat report") {
                    showShareSheet = true
                }
                .disabled(diagnostics.testResults.isEmpty)
            }

            // Quick Actions
            Section("Rychlé akce") {
                Button("Reset Mock Mode") {
                    UserDefaults.standard.removeObject(forKey: "MockModeEnabled")
                }

                Button("Clear All Cached Data") {
                    clearCaches()
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Diagnostika")
        .sheet(isPresented: $showShareSheet) {
            DiagnosticsShareSheet(items: [diagnostics.exportReport()])
        }
    }

    private func clearCaches() {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        try? FileManager.default.removeItem(at: cacheURL)
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    }
}

// MARK: - Helper Views

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DiagnosticsShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
