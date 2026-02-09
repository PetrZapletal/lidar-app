import Foundation

/// Protokol pro network komunikaci s backendem
@MainActor
protocol NetworkServiceProtocol: AnyObject {
    /// Base URL backendu
    var baseURL: URL? { get }

    /// Zda je backend dostupný
    var isConnected: Bool { get }

    /// Otestuj konektivitu
    func checkConnectivity() async -> Bool

    /// HTTP request
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable)?
    ) async throws -> T

    /// Upload souboru
    func uploadFile(
        endpoint: String,
        fileURL: URL,
        onProgress: @escaping (Float) -> Void
    ) async throws -> Data

    /// Download souboru
    func downloadFile(
        endpoint: String,
        destinationURL: URL,
        onProgress: @escaping (Float) -> Void
    ) async throws
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}


