import Foundation

// MARK: - Network Service

/// Production implementation of NetworkServiceProtocol.
/// Communicates with the backend over HTTPS using self-signed certificates via Tailscale.
/// Provides JSON request/response handling, multipart file uploads, and file downloads
/// with progress tracking and exponential backoff retry for transient failures.
@MainActor
@Observable
final class NetworkService: NetworkServiceProtocol {

    // MARK: - Constants

    private enum Constants {
        static let maxRetryAttempts = 3
        static let initialRetryDelaySeconds: TimeInterval = 1.0
        static let requestTimeoutSeconds: TimeInterval = 30.0
        static let uploadTimeoutSeconds: TimeInterval = 300.0
        static let downloadTimeoutSeconds: TimeInterval = 300.0
        static let healthCheckTimeoutSeconds: TimeInterval = 5.0
        static let multipartBoundary = "LidarAPP-Boundary-\(UUID().uuidString)"
    }

    // MARK: - Properties

    var baseURL: URL? {
        let settings = DebugSettings.shared
        return URL(string: "https://\(settings.tailscaleIP):\(settings.serverPort)")
    }

    private(set) var isConnected: Bool = false

    @ObservationIgnored
    private let interceptor: RequestInterceptor
    @ObservationIgnored
    private let uploadDelegate: UploadProgressDelegate
    @ObservationIgnored
    private let downloadDelegate: DownloadProgressDelegate

    @ObservationIgnored
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.requestTimeoutSeconds
        config.timeoutIntervalForResource = Constants.requestTimeoutSeconds * 2
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: SelfSignedCertDelegate.shared, delegateQueue: nil)
    }()

    @ObservationIgnored
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    @ObservationIgnored
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Initialization

    init(interceptor: RequestInterceptor = RequestInterceptor()) {
        self.interceptor = interceptor
        self.uploadDelegate = UploadProgressDelegate()
        self.downloadDelegate = DownloadProgressDelegate()
    }

    // MARK: - Connectivity

    func checkConnectivity() async -> Bool {
        guard let base = baseURL else {
            isConnected = false
            warningLog("No base URL configured for connectivity check", category: .logCategoryNetwork)
            return false
        }

        let healthURL = base.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Constants.healthCheckTimeoutSeconds

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                isConnected = true
                debugLog("Backend connectivity check passed", category: .logCategoryNetwork)
                return true
            }
            isConnected = false
            warningLog("Backend health check returned non-200 status", category: .logCategoryNetwork)
            return false
        } catch {
            isConnected = false
            warningLog("Backend connectivity check failed: \(error.localizedDescription)", category: .logCategoryNetwork)
            return false
        }
    }

    // MARK: - HTTP Request

    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable)?
    ) async throws -> T {
        let urlRequest = try buildRequest(endpoint: endpoint, method: method, body: body)

        let (data, response) = try await performRequestWithRetry(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverUnreachable
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw NetworkError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            let decoded = try jsonDecoder.decode(T.self, from: data)
            return decoded
        } catch {
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "non-UTF8"
            errorLog("JSON decoding failed for \(T.self): \(error.localizedDescription). Response preview: \(preview)", category: .logCategoryNetwork)
            throw NetworkError.decodingFailed("\(error.localizedDescription)")
        }
    }

    // MARK: - File Upload (Multipart)

    func uploadFile(
        endpoint: String,
        fileURL: URL,
        onProgress: @escaping (Float) -> Void
    ) async throws -> Data {
        guard let base = baseURL else {
            throw NetworkError.invalidURL("No base URL configured")
        }

        let url = base.appendingPathComponent(endpoint)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NetworkError.uploadFailed("File does not exist: \(fileURL.lastPathComponent)")
        }

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw NetworkError.uploadFailed("Cannot read file: \(error.localizedDescription)")
        }

        // Build multipart body
        let boundary = Constants.multipartBoundary
        var bodyData = Data()

        let fileName = fileURL.lastPathComponent
        let mimeType = mimeTypeForExtension(fileURL.pathExtension)

        bodyData.append("--\(boundary)\r\n")
        bodyData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        bodyData.append("Content-Type: \(mimeType)\r\n\r\n")
        bodyData.append(fileData)
        bodyData.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.timeoutInterval = Constants.uploadTimeoutSeconds
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")

        await interceptor.intercept(request: &request)
        interceptor.logRequest(request)

        // Use upload session with progress delegate
        let uploadConfig = URLSessionConfiguration.default
        uploadConfig.timeoutIntervalForRequest = Constants.uploadTimeoutSeconds
        uploadConfig.timeoutIntervalForResource = Constants.uploadTimeoutSeconds * 2

        let progressDelegate = UploadProgressDelegate()
        progressDelegate.onProgress = { progress in
            Task { @MainActor in
                onProgress(progress)
            }
        }

        let uploadSession = URLSession(
            configuration: uploadConfig,
            delegate: progressDelegate,
            delegateQueue: nil
        )

        defer { uploadSession.finishTasksAndInvalidate() }

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (data, response) = try await uploadSession.upload(for: request, from: bodyData)
            let duration = CFAbsoluteTimeGetCurrent() - startTime

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.uploadFailed("Invalid server response")
            }

            interceptor.logResponse(httpResponse, data: data, duration: duration)

            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Upload rejected by server"
                throw NetworkError.uploadFailed("Server returned \(httpResponse.statusCode): \(message)")
            }

            onProgress(1.0)
            infoLog("File upload completed: \(fileName) [\(formatBytes(fileData.count))] in \(Int(duration * 1000))ms", category: .logCategoryNetwork)
            return data
        } catch let error as NetworkError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw NetworkError.timeout
        } catch {
            throw NetworkError.uploadFailed(error.localizedDescription)
        }
    }

    // MARK: - File Download

    func downloadFile(
        endpoint: String,
        destinationURL: URL,
        onProgress: @escaping (Float) -> Void
    ) async throws {
        guard let base = baseURL else {
            throw NetworkError.invalidURL("No base URL configured")
        }

        let url = base.appendingPathComponent(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.timeoutInterval = Constants.downloadTimeoutSeconds

        await interceptor.intercept(request: &request)
        interceptor.logRequest(request)

        // Use download session with progress delegate
        let downloadConfig = URLSessionConfiguration.default
        downloadConfig.timeoutIntervalForRequest = Constants.downloadTimeoutSeconds
        downloadConfig.timeoutIntervalForResource = Constants.downloadTimeoutSeconds * 2

        let progressDelegate = DownloadProgressDelegate()
        progressDelegate.onProgress = { progress in
            Task { @MainActor in
                onProgress(progress)
            }
        }

        let downloadSession = URLSession(
            configuration: downloadConfig,
            delegate: progressDelegate,
            delegateQueue: nil
        )

        defer { downloadSession.finishTasksAndInvalidate() }

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (tempURL, response) = try await downloadSession.download(for: request)
            let duration = CFAbsoluteTimeGetCurrent() - startTime

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.downloadFailed("Invalid server response")
            }

            interceptor.logResponse(httpResponse, data: nil, duration: duration)

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw NetworkError.downloadFailed("Server returned \(httpResponse.statusCode)")
            }

            // Move downloaded file to destination
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            // Ensure parent directory exists
            let parentDir = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

            try fileManager.moveItem(at: tempURL, to: destinationURL)

            onProgress(1.0)

            let fileSize = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
            infoLog("File download completed: \(destinationURL.lastPathComponent) [\(formatBytes(Int(fileSize)))] in \(Int(duration * 1000))ms", category: .logCategoryNetwork)

        } catch let error as NetworkError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw NetworkError.timeout
        } catch {
            throw NetworkError.downloadFailed(error.localizedDescription)
        }
    }

    // MARK: - Private: Request Building

    private func buildRequest(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable)?
    ) throws -> URLRequest {
        guard let base = baseURL else {
            throw NetworkError.invalidURL("No base URL configured")
        }

        let url = base.appendingPathComponent(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = Constants.requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            do {
                request.httpBody = try jsonEncoder.encode(AnyEncodable(body))
            } catch {
                errorLog("Failed to encode request body: \(error.localizedDescription)", category: .logCategoryNetwork)
                throw NetworkError.requestFailed(statusCode: 0, message: "Body encoding failed: \(error.localizedDescription)")
            }
        }

        return request
    }

    // MARK: - Private: Retry Logic

    /// Performs an HTTP request with exponential backoff retry for transient errors.
    /// Retries on 5xx server errors and timeout errors up to `maxRetryAttempts`.
    private func performRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?
        var urlRequest = request

        await interceptor.intercept(request: &urlRequest)

        for attempt in 0..<Constants.maxRetryAttempts {
            // Check for cancellation before each attempt
            try Task.checkCancellation()

            interceptor.logRequest(urlRequest)
            let startTime = CFAbsoluteTimeGetCurrent()

            do {
                let (data, response) = try await session.data(for: urlRequest)
                let duration = CFAbsoluteTimeGetCurrent() - startTime

                if let httpResponse = response as? HTTPURLResponse {
                    interceptor.logResponse(httpResponse, data: data, duration: duration)

                    // Retry on 5xx server errors
                    if httpResponse.statusCode >= 500 && attempt < Constants.maxRetryAttempts - 1 {
                        let message = String(data: data, encoding: .utf8) ?? "Server error"
                        lastError = NetworkError.requestFailed(statusCode: httpResponse.statusCode, message: message)
                        let delay = retryDelay(attempt: attempt)
                        warningLog("Server error \(httpResponse.statusCode), retrying in \(delay)s (attempt \(attempt + 1)/\(Constants.maxRetryAttempts))", category: .logCategoryNetwork)
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                }

                return (data, response)

            } catch let error as URLError where error.code == .timedOut {
                lastError = NetworkError.timeout
                if attempt < Constants.maxRetryAttempts - 1 {
                    let delay = retryDelay(attempt: attempt)
                    warningLog("Request timed out, retrying in \(delay)s (attempt \(attempt + 1)/\(Constants.maxRetryAttempts))", category: .logCategoryNetwork)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
                lastError = NetworkError.serverUnreachable
                if attempt < Constants.maxRetryAttempts - 1 {
                    let delay = retryDelay(attempt: attempt)
                    warningLog("Connection failed, retrying in \(delay)s (attempt \(attempt + 1)/\(Constants.maxRetryAttempts))", category: .logCategoryNetwork)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            } catch is CancellationError {
                debugLog("Request cancelled: \(urlRequest.url?.absoluteString ?? "nil")", category: .logCategoryNetwork)
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < Constants.maxRetryAttempts - 1 {
                    let delay = retryDelay(attempt: attempt)
                    warningLog("Request failed (\(error.localizedDescription)), retrying in \(delay)s (attempt \(attempt + 1)/\(Constants.maxRetryAttempts))", category: .logCategoryNetwork)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
        }

        // All retries exhausted
        if let networkError = lastError as? NetworkError {
            throw networkError
        }
        throw lastError ?? NetworkError.serverUnreachable
    }

    /// Calculate exponential backoff delay: 1s, 2s, 4s, ...
    private func retryDelay(attempt: Int) -> TimeInterval {
        Constants.initialRetryDelaySeconds * pow(2.0, Double(attempt))
    }

    // MARK: - Private: Helpers

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "ply":
            return "application/x-ply"
        case "obj":
            return "text/plain"
        case "usdz":
            return "model/vnd.usdz+zip"
        case "glb":
            return "model/gltf-binary"
        case "json":
            return "application/json"
        case "zip":
            return "application/zip"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        default:
            return "application/octet-stream"
        }
    }

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

// MARK: - Upload Progress Delegate

/// URLSession delegate that tracks upload progress and handles self-signed certificates.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDelegate {

    var onProgress: ((Float) -> Void)?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        onProgress?(min(progress, 1.0))
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        SelfSignedCertDelegate.shared.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        SelfSignedCertDelegate.shared.urlSession(session, task: task, didReceive: challenge, completionHandler: completionHandler)
    }
}

// MARK: - Download Progress Delegate

/// URLSession delegate that tracks download progress and handles self-signed certificates.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, URLSessionDelegate {

    var onProgress: ((Float) -> Void)?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        onProgress?(min(progress, 1.0))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // File is handled by the async download(for:) API
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        SelfSignedCertDelegate.shared.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        SelfSignedCertDelegate.shared.urlSession(session, task: task, didReceive: challenge, completionHandler: completionHandler)
    }
}

// MARK: - AnyEncodable Wrapper

/// Type-erased Encodable wrapper to support `any Encodable` in generic contexts.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        self._encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - Data Extension

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
