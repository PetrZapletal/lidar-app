import Foundation

/// Main API client for backend communication
actor APIClient {

    // MARK: - Configuration

    struct Configuration {
        let baseURL: URL
        var timeout: TimeInterval = 30
        var maxRetries: Int = 3
        var retryDelay: TimeInterval = 1.0

        static var `default`: Configuration {
            Configuration(baseURL: URL(string: "https://api.lidarapp.com/v1")!)
        }

        static var development: Configuration {
            Configuration(baseURL: URL(string: "http://localhost:8080/v1")!)
        }
    }

    // MARK: - API Endpoints

    enum Endpoint {
        case createScan
        case getScan(id: String)
        case uploadScanData(scanId: String)
        case startProcessing(scanId: String)
        case getProcessingStatus(scanId: String)
        case downloadModel(scanId: String, format: String)
        case listScans
        case deleteScan(id: String)

        // User endpoints
        case currentUser
        case updateUser
        case getUserScans

        var path: String {
            switch self {
            case .createScan: return "/scans"
            case .getScan(let id): return "/scans/\(id)"
            case .uploadScanData(let scanId): return "/scans/\(scanId)/upload"
            case .startProcessing(let scanId): return "/scans/\(scanId)/process"
            case .getProcessingStatus(let scanId): return "/scans/\(scanId)/status"
            case .downloadModel(let scanId, let format): return "/scans/\(scanId)/download?format=\(format)"
            case .listScans: return "/scans"
            case .deleteScan(let id): return "/scans/\(id)"
            case .currentUser: return "/users/me"
            case .updateUser: return "/users/me"
            case .getUserScans: return "/users/me/scans"
            }
        }

        var method: HTTPMethod {
            switch self {
            case .createScan, .uploadScanData, .startProcessing:
                return .post
            case .getScan, .getProcessingStatus, .downloadModel, .listScans, .currentUser, .getUserScans:
                return .get
            case .updateUser:
                return .patch
            case .deleteScan:
                return .delete
            }
        }
    }

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    // MARK: - Error Types

    enum APIError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case httpError(statusCode: Int, message: String?)
        case decodingError(Error)
        case encodingError(Error)
        case unauthorized
        case notFound
        case serverError
        case rateLimited(retryAfter: TimeInterval?)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            case .httpError(let code, let message): return "HTTP \(code): \(message ?? "Unknown error")"
            case .decodingError(let error): return "Decoding error: \(error.localizedDescription)"
            case .encodingError(let error): return "Encoding error: \(error.localizedDescription)"
            case .unauthorized: return "Unauthorized - please log in again"
            case .notFound: return "Resource not found"
            case .serverError: return "Server error - please try again later"
            case .rateLimited(let retry): return "Rate limited\(retry.map { " - retry after \(Int($0))s" } ?? "")"
            case .cancelled: return "Request cancelled"
            }
        }
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var authToken: String?

    // MARK: - Initialization

    init(configuration: Configuration = .default) {
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.waitsForConnectivity = true

        self.session = URLSession(configuration: sessionConfig)

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Authentication

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Request Building

    private func buildRequest(
        endpoint: Endpoint,
        body: Data? = nil,
        additionalHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        guard let url = URL(string: endpoint.path, relativeTo: configuration.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = body

        // Default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Auth header
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Additional headers
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    // MARK: - Request Execution

    func request<T: Decodable>(
        _ endpoint: Endpoint,
        body: Encodable? = nil,
        responseType: T.Type
    ) async throws -> T {
        var bodyData: Data?

        if let body = body {
            do {
                bodyData = try encoder.encode(body)
            } catch {
                throw APIError.encodingError(error)
            }
        }

        let request = try buildRequest(endpoint: endpoint, body: bodyData)

        return try await executeWithRetry(request: request, responseType: responseType)
    }

    func request(_ endpoint: Endpoint, body: Encodable? = nil) async throws {
        var bodyData: Data?

        if let body = body {
            do {
                bodyData = try encoder.encode(body)
            } catch {
                throw APIError.encodingError(error)
            }
        }

        let request = try buildRequest(endpoint: endpoint, body: bodyData)

        _ = try await executeWithRetry(request: request, responseType: EmptyResponse.self)
    }

    private func executeWithRetry<T: Decodable>(
        request: URLRequest,
        responseType: T.Type,
        attempt: Int = 1
    ) async throws -> T {
        do {
            return try await execute(request: request, responseType: responseType)
        } catch let error as APIError {
            // Don't retry certain errors
            switch error {
            case .unauthorized, .notFound, .cancelled:
                throw error
            case .rateLimited(let retryAfter):
                if attempt < configuration.maxRetries {
                    let delay = retryAfter ?? configuration.retryDelay * Double(attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await executeWithRetry(request: request, responseType: responseType, attempt: attempt + 1)
                }
                throw error
            case .serverError, .networkError:
                if attempt < configuration.maxRetries {
                    let delay = configuration.retryDelay * Double(attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await executeWithRetry(request: request, responseType: responseType, attempt: attempt + 1)
                }
                throw error
            default:
                throw error
            }
        }
    }

    private func execute<T: Decodable>(
        request: URLRequest,
        responseType: T.Type
    ) async throws -> T {
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw APIError.cancelled
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(NSError(domain: "Invalid response", code: -1))
        }

        // Handle status codes
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) }
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw APIError.serverError
        default:
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        // Decode response
        do {
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Download

    func download(from endpoint: Endpoint) async throws -> URL {
        guard let url = URL(string: endpoint.path, relativeTo: configuration.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (tempURL, response) = try await session.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
                message: nil
            )
        }

        // Move to permanent location
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = url.lastPathComponent
        let destinationURL = documentsURL.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        return destinationURL
    }
}

// MARK: - Response Types

struct EmptyResponse: Decodable {}

struct APIResponse<T: Decodable>: Decodable {
    let data: T
    let meta: ResponseMeta?
}

struct ResponseMeta: Decodable {
    let requestId: String?
    let timestamp: Date?
}

// MARK: - Scan API Models

struct CreateScanRequest: Encodable {
    let name: String
    let deviceInfo: DeviceInfo
    let settings: ScanSettings?

    struct DeviceInfo: Encodable {
        let model: String
        let osVersion: String
        let hasLiDAR: Bool
    }

    struct ScanSettings: Encodable {
        let quality: String?
        let meshEnabled: Bool?
        let colorEnabled: Bool?
    }
}

struct ScanResponse: Decodable {
    let id: String
    let name: String
    let status: String
    let createdAt: Date
    let updatedAt: Date
    let processingProgress: Float?
    let downloadURLs: [String: String]?
}

struct ProcessingStatusResponse: Decodable {
    let scanId: String
    let status: ProcessingStatus
    let progress: Float
    let currentStage: String?
    let error: String?
    let estimatedTimeRemaining: TimeInterval?

    enum ProcessingStatus: String, Decodable {
        case pending
        case uploading
        case queued
        case processing
        case completed
        case failed
    }
}

struct UploadResponse: Decodable {
    let uploadId: String
    let bytesReceived: Int
    let complete: Bool
}

// MARK: - Convenience Methods

extension APIClient {

    func createScan(name: String) async throws -> ScanResponse {
        let request = CreateScanRequest(
            name: name,
            deviceInfo: .init(
                model: UIDevice.current.model,
                osVersion: UIDevice.current.systemVersion,
                hasLiDAR: DeviceCapabilities.hasLiDAR
            ),
            settings: nil
        )

        return try await self.request(.createScan, body: request, responseType: ScanResponse.self)
    }

    func getScan(id: String) async throws -> ScanResponse {
        try await request(.getScan(id: id), responseType: ScanResponse.self)
    }

    func getProcessingStatus(scanId: String) async throws -> ProcessingStatusResponse {
        try await request(.getProcessingStatus(scanId: scanId), responseType: ProcessingStatusResponse.self)
    }

    func startProcessing(scanId: String) async throws {
        try await request(.startProcessing(scanId: scanId))
    }

    func downloadModel(scanId: String, format: String = "usdz") async throws -> URL {
        try await download(from: .downloadModel(scanId: scanId, format: format))
    }

    func listScans() async throws -> [ScanResponse] {
        try await request(.listScans, responseType: [ScanResponse].self)
    }

    func deleteScan(id: String) async throws {
        try await request(.deleteScan(id: id))
    }
}
