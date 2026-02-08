import Foundation
import SwiftUI

// MARK: - Debug Settings

/// Centralized debug configuration using @AppStorage
/// Available in both Debug and Release builds
/// Debug Stream features are controlled by runtime `debugStreamEnabled` flag
@MainActor
@Observable
final class DebugSettings {
    static let shared = DebugSettings()

    // MARK: - Raw Data Pipeline Settings

    /// Enable raw data upload mode (bypass edge processing)
    /// Default: true for testing
    @ObservationIgnored
    @AppStorage("debug.rawData.enabled") var rawDataModeEnabled = true

    /// Tailscale IP address for debug server
    @ObservationIgnored
    @AppStorage("debug.rawData.tailscaleIP") var tailscaleIP = "100.96.188.18"

    /// Debug server port (8444 external, maps to 8443 in Docker)
    @ObservationIgnored
    @AppStorage("debug.rawData.port") var serverPort = 8444

    /// Include depth maps in raw upload
    @ObservationIgnored
    @AppStorage("debug.rawData.includeDepth") var includeDepthMaps = true

    /// Include confidence maps
    @ObservationIgnored
    @AppStorage("debug.rawData.includeConfidence") var includeConfidenceMaps = true

    /// Texture frame quality (0.0-1.0)
    @ObservationIgnored
    @AppStorage("debug.rawData.textureQuality") var textureQuality = 0.95

    /// Maximum texture frames to capture
    @ObservationIgnored
    @AppStorage("debug.rawData.maxTextureFrames") var maxTextureFrames = 500

    // MARK: - Debug Stream Settings

    /// Enable debug info streaming
    @ObservationIgnored
    @AppStorage("debug.stream.enabled") var debugStreamEnabled = true

    /// Debug stream server IP (can be different from raw data server)
    @ObservationIgnored
    @AppStorage("debug.stream.serverIP") var debugStreamServerIP = "100.96.188.18"

    /// Debug stream port (8444 external, maps to 8443 in Docker)
    @ObservationIgnored
    @AppStorage("debug.stream.port") var debugStreamPort = 8444

    /// Stream mode: "realtime" (WebSocket) or "batch" (HTTP)
    @ObservationIgnored
    @AppStorage("debug.stream.mode") var debugStreamMode = "batch"

    /// Batch interval in seconds
    @ObservationIgnored
    @AppStorage("debug.stream.batchInterval") var batchInterval = 5.0

    /// Enabled debug categories (comma-separated)
    @ObservationIgnored
    @AppStorage("debug.stream.categories") var enabledCategoriesString = "appState,performance,arSession,processing,logs"

    /// Verbose logging
    @ObservationIgnored
    @AppStorage("debug.stream.verbose") var verboseLogging = false

    // MARK: - Computed Properties

    /// Full URL for raw data upload (HTTPS)
    var rawDataBaseURL: URL? {
        URL(string: "https://\(tailscaleIP):\(serverPort)")
    }

    /// Full URL for raw scan upload endpoint
    var rawScanUploadURL: URL? {
        guard let base = rawDataBaseURL else { return nil }
        return URL(string: "\(base.absoluteString)/api/v1/debug/scans/raw")
    }

    /// Full URL for debug stream WebSocket (WSS for HTTPS)
    var debugStreamWebSocketURL: URL? {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        return URL(string: "wss://\(debugStreamServerIP):\(debugStreamPort)/api/v1/debug/stream/\(deviceId)")
    }

    /// Full URL for debug batch upload (HTTPS)
    var debugBatchUploadURL: URL? {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        return URL(string: "https://\(debugStreamServerIP):\(debugStreamPort)/api/v1/debug/events/\(deviceId)")
    }

    /// Parse enabled categories from string
    var enabledCategories: Set<DebugCategory> {
        get {
            Set(enabledCategoriesString.split(separator: ",").compactMap {
                DebugCategory(rawValue: String($0).trimmingCharacters(in: .whitespaces))
            })
        }
        set {
            enabledCategoriesString = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    /// Check if a specific category is enabled
    func isCategoryEnabled(_ category: DebugCategory) -> Bool {
        enabledCategories.contains(category)
    }

    // MARK: - Connection Testing

    /// Test connection to debug server
    func testConnection() async -> (success: Bool, message: String, latencyMs: Double?) {
        guard let base = rawDataBaseURL,
              let url = URL(string: "\(base.absoluteString)/health") else {
            return (false, "Invalid URL configuration", nil)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Create URLSession that accepts self-signed certificates
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 10.0
        let session = URLSession(configuration: config, delegate: SelfSignedCertDelegate.shared, delegateQueue: nil)

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5.0

            let (_, response) = try await session.data(for: request)
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    return (true, "Connected successfully", latency)
                } else {
                    return (false, "Server returned status \(httpResponse.statusCode)", latency)
                }
            }
            return (false, "Invalid response", latency)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                return (false, "Connection timed out", nil)
            case .cannotConnectToHost:
                return (false, "Cannot connect to host - check Tailscale", nil)
            case .networkConnectionLost:
                return (false, "Network connection lost", nil)
            case .serverCertificateUntrusted:
                return (false, "Certificate not trusted", nil)
            default:
                return (false, "Network error: \(error.localizedDescription)", nil)
            }
        } catch {
            return (false, "Error: \(error.localizedDescription)", nil)
        }
    }

    // MARK: - Reset

    /// Reset all debug settings to defaults
    func resetToDefaults() {
        rawDataModeEnabled = true  // Keep enabled for testing
        tailscaleIP = "100.96.188.18"
        serverPort = 8444  // Docker external port (maps to 8443)
        includeDepthMaps = true
        includeConfidenceMaps = true
        textureQuality = 0.95
        maxTextureFrames = 500

        debugStreamEnabled = true
        debugStreamServerIP = "100.96.188.18"
        debugStreamPort = 8444  // Docker external port (maps to 8443)
        debugStreamMode = "batch"
        batchInterval = 5.0
        enabledCategoriesString = "appState,performance,arSession,processing,logs"
        verboseLogging = false
    }
}

// MARK: - Debug Categories

enum DebugCategory: String, CaseIterable, Codable, Identifiable {
    case appState = "appState"
    case performance = "performance"
    case arSession = "arSession"
    case processing = "processing"
    case network = "network"
    case logs = "logs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appState: return "App State"
        case .performance: return "Performance"
        case .arSession: return "AR Session"
        case .processing: return "Processing"
        case .network: return "Network"
        case .logs: return "Logs"
        }
    }

    var icon: String {
        switch self {
        case .appState: return "app.badge"
        case .performance: return "speedometer"
        case .arSession: return "arkit"
        case .processing: return "cpu"
        case .network: return "network"
        case .logs: return "doc.text"
        }
    }
}

// MARK: - Stream Mode

enum DebugStreamMode: String, CaseIterable, Identifiable {
    case realtime = "realtime"
    case batch = "batch"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .realtime: return "Real-time (WebSocket)"
        case .batch: return "Batch (HTTP)"
        }
    }
}

// MARK: - Self-Signed Certificate Delegate

/// URLSession delegate that accepts self-signed certificates for debug server
/// WARNING: Only use for development/debug purposes
final class SelfSignedCertDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    static let shared = SelfSignedCertDelegate()

    // Session-level authentication challenge
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    // Task-level authentication challenge (required for data tasks)
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    private func handleChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Accept self-signed certificates for debug server
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            // Bypass certificate validation for debug purposes
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
