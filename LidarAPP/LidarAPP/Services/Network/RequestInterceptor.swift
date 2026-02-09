import Foundation

// MARK: - Request Interceptor

/// Intercepts HTTP requests to add authentication headers and log request/response cycles.
/// Uses KeychainService to retrieve stored auth tokens for Bearer authentication.
@MainActor
final class RequestInterceptor {

    // MARK: - Properties

    private let keychain: KeychainService

    // MARK: - Initialization

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
    }

    // MARK: - Request Interception

    /// Add authorization header if a valid token exists in the keychain.
    func intercept(request: inout URLRequest) async {
        do {
            let token = try await keychain.loadString(forKey: KeychainKey.accessToken)
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                debugLog("Auth token attached to request", category: .logCategoryNetwork)
            }
        } catch {
            // No token available - proceed without auth header (anonymous request)
            debugLog("No auth token available, proceeding without authorization", category: .logCategoryNetwork)
        }
    }

    // MARK: - Logging

    /// Log outgoing request details for debugging.
    func logRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "UNKNOWN"
        let url = request.url?.absoluteString ?? "nil"
        let bodySize = request.httpBody?.count ?? 0

        var message = "\(method) \(url)"
        if bodySize > 0 {
            message += " [body: \(formatBytes(bodySize))]"
        }

        debugLog(">>> \(message)", category: .logCategoryNetwork)

        // Log headers in verbose mode (excluding sensitive values)
        if let headers = request.allHTTPHeaderFields {
            let safeHeaders = headers.map { key, value in
                if key.lowercased() == "authorization" {
                    return "\(key): Bearer ***"
                }
                return "\(key): \(value)"
            }
            debugLog("    Headers: \(safeHeaders.joined(separator: ", "))", category: .logCategoryNetwork)
        }
    }

    /// Log incoming response details with timing information.
    func logResponse(_ response: HTTPURLResponse, data: Data?, duration: TimeInterval) {
        let statusCode = response.statusCode
        let url = response.url?.absoluteString ?? "nil"
        let dataSize = data?.count ?? 0
        let durationMs = Int(duration * 1000)

        let statusEmoji: String
        switch statusCode {
        case 200..<300:
            statusEmoji = "OK"
        case 300..<400:
            statusEmoji = "REDIRECT"
        case 400..<500:
            statusEmoji = "CLIENT_ERR"
        case 500..<600:
            statusEmoji = "SERVER_ERR"
        default:
            statusEmoji = "UNKNOWN"
        }

        let message = "<<< \(statusCode) \(statusEmoji) \(url) [\(formatBytes(dataSize)), \(durationMs)ms]"

        if statusCode >= 400 {
            errorLog(message, category: .logCategoryNetwork)

            // Log response body for error responses (truncated)
            if let data = data, let body = String(data: data, encoding: .utf8) {
                let truncated = body.count > 500 ? String(body.prefix(500)) + "..." : body
                errorLog("    Response body: \(truncated)", category: .logCategoryNetwork)
            }
        } else {
            debugLog(message, category: .logCategoryNetwork)
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes)B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1fKB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1fMB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}
