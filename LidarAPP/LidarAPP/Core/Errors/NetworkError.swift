import Foundation

/// Chyby síťové komunikace
enum NetworkError: Error, LocalizedError {
    case notConnected
    case invalidURL(String)
    case requestFailed(statusCode: Int, message: String)
    case decodingFailed(String)
    case timeout
    case serverUnreachable
    case uploadFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Žádné připojení k serveru"
        case .invalidURL(let url):
            return "Neplatná URL: \(url)"
        case .requestFailed(let code, let message):
            return "Server vrátil chybu \(code): \(message)"
        case .decodingFailed(let detail):
            return "Nepodařilo se dekódovat odpověď: \(detail)"
        case .timeout:
            return "Požadavek vypršel"
        case .serverUnreachable:
            return "Server není dostupný - zkontrolujte Tailscale"
        case .uploadFailed(let reason):
            return "Upload selhal: \(reason)"
        case .downloadFailed(let reason):
            return "Download selhal: \(reason)"
        }
    }
}
