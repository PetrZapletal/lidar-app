import Foundation

/// Chyby autentizace
enum AuthError: Error, LocalizedError {
    case notAuthenticated
    case signInFailed(String)
    case tokenExpired
    case keychainError(String)
    case appleSignInCancelled
    case appleSignInFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Uživatel není přihlášen"
        case .signInFailed(let reason):
            return "Přihlášení selhalo: \(reason)"
        case .tokenExpired:
            return "Session vypršela, přihlaste se znovu"
        case .keychainError(let detail):
            return "Keychain chyba: \(detail)"
        case .appleSignInCancelled:
            return "Přihlášení přes Apple zrušeno"
        case .appleSignInFailed(let reason):
            return "Apple Sign In selhal: \(reason)"
        }
    }
}
