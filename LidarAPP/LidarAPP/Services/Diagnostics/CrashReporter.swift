import Foundation
import MetricKit
import UIKit

/// Collects crash reports and diagnostics using Apple's MetricKit
/// Reports are delivered within 24 hours of the crash
@MainActor
final class CrashReporter: NSObject {

    static let shared = CrashReporter()

    private var diagnosticPayloads: [MXDiagnosticPayload] = []
    private var metricPayloads: [MXMetricPayload] = []

    private override init() {
        super.init()
    }

    /// Start collecting crash reports and metrics
    func start() {
        MXMetricManager.shared.add(self)
        print("CrashReporter: Started collecting diagnostics")
    }

    /// Stop collecting
    func stop() {
        MXMetricManager.shared.remove(self)
    }

    /// Get all collected diagnostic payloads
    func getDiagnostics() -> [MXDiagnosticPayload] {
        return diagnosticPayloads
    }

    /// Get all collected metric payloads
    func getMetrics() -> [MXMetricPayload] {
        return metricPayloads
    }

    /// Export diagnostics to JSON for debugging
    func exportDiagnosticsJSON() -> String? {
        guard !diagnosticPayloads.isEmpty else { return nil }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        var reports: [[String: Any]] = []

        for payload in diagnosticPayloads {
            var report: [String: Any] = [
                "timeStampBegin": payload.timeStampBegin.description,
                "timeStampEnd": payload.timeStampEnd.description
            ]

            // Crash diagnostics
            if let crashes = payload.crashDiagnostics {
                report["crashes"] = crashes.map { crash in
                    [
                        "terminationReason": crash.terminationReason ?? "unknown",
                        "signal": crash.signal?.description ?? "unknown",
                        "exceptionType": crash.exceptionType?.description ?? "unknown",
                        "exceptionCode": crash.exceptionCode?.description ?? "unknown",
                        "virtualMemoryRegionInfo": crash.virtualMemoryRegionInfo ?? "unknown"
                    ]
                }
            }

            // Hang diagnostics
            if let hangs = payload.hangDiagnostics {
                report["hangs"] = hangs.count
            }

            // CPU exceptions
            if let cpuExceptions = payload.cpuExceptionDiagnostics {
                report["cpuExceptions"] = cpuExceptions.count
            }

            // Disk write exceptions
            if let diskExceptions = payload.diskWriteExceptionDiagnostics {
                report["diskWriteExceptions"] = diskExceptions.count
            }

            reports.append(report)
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: reports, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return nil
    }

    /// Save diagnostics to file
    func saveDiagnosticsToFile() -> URL? {
        guard let json = exportDiagnosticsJSON() else { return nil }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDir.appendingPathComponent("crash_diagnostics_\(Date().timeIntervalSince1970).json")

        do {
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
            print("CrashReporter: Saved diagnostics to \(fileURL)")
            return fileURL
        } catch {
            print("CrashReporter: Failed to save diagnostics: \(error)")
            return nil
        }
    }

    // MARK: - Backend Upload

    /// Send crash report to debug backend
    func sendCrashToBackend(
        crashType: String,
        errorMessage: String,
        stackTrace: String? = nil,
        userInfo: [String: Any]? = nil
    ) {
        guard DebugSettings.shared.rawDataModeEnabled,
              let baseURL = DebugSettings.shared.rawDataBaseURL else {
            return
        }

        let crashURL = baseURL.appendingPathComponent("/api/v1/debug/crashes")

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        var report: [String: Any] = [
            "device_id": deviceId,
            "app_version": appVersion,
            "build_number": buildNumber,
            "ios_version": UIDevice.current.systemVersion,
            "device_model": UIDevice.current.model,
            "crash_type": crashType,
            "error_message": errorMessage,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        if let stackTrace = stackTrace {
            report["stack_trace"] = stackTrace
        }

        if let userInfo = userInfo {
            report["user_info"] = userInfo
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: report) else {
            print("CrashReporter: Failed to serialize crash report")
            return
        }

        var request = URLRequest(url: crashURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        // Use custom session for self-signed certs
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config, delegate: SelfSignedCertDelegate.shared, delegateQueue: nil)

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("CrashReporter: Failed to send to backend - \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("CrashReporter: Successfully sent crash report to backend")
            } else {
                print("CrashReporter: Backend returned error")
            }
        }.resume()
    }

    /// Send MetricKit crash to backend
    private func sendMetricKitCrashToBackend(_ crash: MXCrashDiagnostic) {
        let jsonData = crash.jsonRepresentation()
        let stackTrace = String(data: jsonData, encoding: .utf8)

        sendCrashToBackend(
            crashType: "MetricKit Crash",
            errorMessage: crash.terminationReason ?? "Unknown termination reason",
            stackTrace: stackTrace,
            userInfo: [
                "signal": crash.signal?.description ?? "unknown",
                "exceptionType": crash.exceptionType?.description ?? "unknown",
                "exceptionCode": crash.exceptionCode?.description ?? "unknown"
            ]
        )
    }
}

// MARK: - MXMetricManagerSubscriber

extension CrashReporter: MXMetricManagerSubscriber {

    /// Called when new diagnostic payloads are available (crashes, hangs, etc.)
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { @MainActor in
            print("CrashReporter: Received \(payloads.count) diagnostic payload(s)")

            for payload in payloads {
                self.diagnosticPayloads.append(payload)

                // Log crash info
                if let crashes = payload.crashDiagnostics {
                    for crash in crashes {
                        print("CrashReporter: Crash detected")
                        print("  - Termination reason: \(crash.terminationReason ?? "unknown")")
                        print("  - Signal: \(crash.signal?.description ?? "unknown")")
                        print("  - Exception type: \(crash.exceptionType?.description ?? "unknown")")

                        // Get the JSON representation for detailed stack trace
                        let jsonData = crash.jsonRepresentation()
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            print("  - Full report: \(jsonString.prefix(500))...")
                        }
                    }
                }

                // Log hangs
                if let hangs = payload.hangDiagnostics {
                    print("CrashReporter: \(hangs.count) hang(s) detected")
                }

                // Send crashes to backend
                if let crashes = payload.crashDiagnostics {
                    for crash in crashes {
                        self.sendMetricKitCrashToBackend(crash)
                    }
                }
            }

            // Auto-save to file
            _ = self.saveDiagnosticsToFile()
        }
    }

    /// Called when new metric payloads are available (performance data)
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        Task { @MainActor in
            print("CrashReporter: Received \(payloads.count) metric payload(s)")
            self.metricPayloads.append(contentsOf: payloads)

            for payload in payloads {
                // Log key metrics
                if let appLaunch = payload.applicationLaunchMetrics {
                    let histogram = appLaunch.histogrammedTimeToFirstDraw
                    print("CrashReporter: Time to first draw: \(histogram)")
                }

                if let memory = payload.memoryMetrics {
                    print("CrashReporter: Peak memory: \(memory.peakMemoryUsage)")
                }
            }
        }
    }
}
