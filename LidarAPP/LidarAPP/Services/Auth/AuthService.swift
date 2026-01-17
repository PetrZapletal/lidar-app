import Foundation
import Combine

/// Manages user authentication and session
@MainActor
@Observable
final class AuthService {

    // MARK: - Published State

    private(set) var currentUser: User?
    private(set) var isAuthenticated: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var authError: AuthError?

    var isLoggedIn: Bool { currentUser != nil }

    // MARK: - Dependencies

    private let keychain: KeychainService
    private let apiBaseURL: URL
    private let session: URLSession

    private var tokens: AuthTokens?

    // MARK: - Initialization

    init(
        apiBaseURL: URL = URL(string: "https://api.lidarapp.com/v1")!,
        keychain: KeychainService = KeychainService()
    ) {
        self.apiBaseURL = apiBaseURL
        self.keychain = keychain

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Session Restoration

    func restoreSession() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Try to load stored tokens
            tokens = try await keychain.load(forKey: KeychainKey.authTokens, as: AuthTokens.self)

            // Check if tokens need refresh
            if let tokens = tokens, tokens.needsRefresh {
                try await refreshTokens()
            }

            // Load stored user
            currentUser = try await keychain.load(forKey: KeychainKey.currentUser, as: User.self)
            isAuthenticated = true

            // Fetch fresh user data
            await fetchCurrentUser()

        } catch {
            // No valid session, user needs to log in
            isAuthenticated = false
            currentUser = nil
        }
    }

    // MARK: - Login

    func login(email: String, password: String) async throws {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        let url = apiBaseURL.appendingPathComponent("auth/login")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200...299:
                let authResponse = try JSONDecoder.apiDecoder.decode(AuthResponse.self, from: data)
                await handleSuccessfulAuth(authResponse)

            case 401:
                throw AuthError.invalidCredentials

            case 429:
                throw AuthError.tooManyAttempts

            default:
                let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
                throw AuthError.serverError(errorResponse?.message ?? "Login failed")
            }
        } catch let error as AuthError {
            authError = error
            throw error
        } catch {
            let authErr = AuthError.networkError(error)
            authError = authErr
            throw authErr
        }
    }

    // MARK: - Register

    func register(email: String, password: String, displayName: String?) async throws {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        let url = apiBaseURL.appendingPathComponent("auth/register")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = ["email": email, "password": password]
        if let displayName = displayName {
            body["displayName"] = displayName
        }
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200...299:
                let authResponse = try JSONDecoder.apiDecoder.decode(AuthResponse.self, from: data)
                await handleSuccessfulAuth(authResponse)

            case 409:
                throw AuthError.emailAlreadyExists

            case 422:
                throw AuthError.invalidEmail

            default:
                let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
                throw AuthError.serverError(errorResponse?.message ?? "Registration failed")
            }
        } catch let error as AuthError {
            authError = error
            throw error
        } catch {
            let authErr = AuthError.networkError(error)
            authError = authErr
            throw authErr
        }
    }

    // MARK: - Logout

    func logout() async {
        isLoading = true
        defer { isLoading = false }

        // Notify server (best effort)
        if let tokens = tokens {
            try? await notifyLogout(accessToken: tokens.accessToken)
        }

        // Clear local state
        await clearSession()
    }

    // MARK: - Token Management

    func getValidAccessToken() async throws -> String {
        guard let tokens = tokens else {
            throw AuthError.notAuthenticated
        }

        if tokens.needsRefresh {
            try await refreshTokens()
        }

        guard let currentTokens = self.tokens else {
            throw AuthError.notAuthenticated
        }

        return currentTokens.accessToken
    }

    private func refreshTokens() async throws {
        guard let currentTokens = tokens else {
            throw AuthError.notAuthenticated
        }

        let url = apiBaseURL.appendingPathComponent("auth/refresh")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["refreshToken": currentTokens.refreshToken]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            await clearSession()
            throw AuthError.sessionExpired
        }

        let refreshResponse = try JSONDecoder.apiDecoder.decode(TokenRefreshResponse.self, from: data)

        let newTokens = AuthTokens(
            accessToken: refreshResponse.accessToken,
            refreshToken: refreshResponse.refreshToken,
            expiresAt: refreshResponse.expiresAt
        )

        self.tokens = newTokens
        try await keychain.save(newTokens, forKey: KeychainKey.authTokens)
    }

    // MARK: - User Management

    private func fetchCurrentUser() async {
        guard let tokens = tokens else { return }

        let url = apiBaseURL.appendingPathComponent("users/me")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return
            }

            let user = try JSONDecoder.apiDecoder.decode(User.self, from: data)
            self.currentUser = user
            try await keychain.save(user, forKey: KeychainKey.currentUser)
        } catch {
            // Silently fail - we have cached user data
        }
    }

    func updateUserPreferences(_ preferences: UserPreferences) async throws {
        guard var user = currentUser, let tokens = tokens else {
            throw AuthError.notAuthenticated
        }

        let url = apiBaseURL.appendingPathComponent("users/me/preferences")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(preferences)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError("Failed to update preferences")
        }

        // Update local user
        user = User(
            id: user.id,
            email: user.email,
            displayName: user.displayName,
            avatarURL: user.avatarURL,
            createdAt: user.createdAt,
            subscription: user.subscription,
            scanCredits: user.scanCredits,
            preferences: preferences
        )
        self.currentUser = user
        try await keychain.save(user, forKey: KeychainKey.currentUser)
    }

    // MARK: - Password Reset

    func requestPasswordReset(email: String) async throws {
        let url = apiBaseURL.appendingPathComponent("auth/forgot-password")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError("Failed to send reset email")
        }
    }

    // MARK: - Social Auth

    func loginWithApple(identityToken: String, authorizationCode: String) async throws {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        let url = apiBaseURL.appendingPathComponent("auth/apple")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = [
            "identityToken": identityToken,
            "authorizationCode": authorizationCode
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError("Apple Sign In failed")
        }

        let authResponse = try JSONDecoder.apiDecoder.decode(AuthResponse.self, from: data)
        await handleSuccessfulAuth(authResponse)
    }

    // MARK: - Private Helpers

    private func handleSuccessfulAuth(_ response: AuthResponse) async {
        self.tokens = response.tokens
        self.currentUser = response.user
        self.isAuthenticated = true

        // Persist to keychain
        do {
            try await keychain.save(response.tokens, forKey: KeychainKey.authTokens)
            try await keychain.save(response.user, forKey: KeychainKey.currentUser)
        } catch {
            print("Failed to persist auth data: \(error)")
        }
    }

    private func clearSession() async {
        tokens = nil
        currentUser = nil
        isAuthenticated = false

        do {
            try await keychain.deleteAll()
        } catch {
            print("Failed to clear keychain: \(error)")
        }
    }

    private func notifyLogout(accessToken: String) async throws {
        let url = apiBaseURL.appendingPathComponent("auth/logout")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        _ = try await session.data(for: request)
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredentials
    case emailAlreadyExists
    case invalidEmail
    case weakPassword
    case notAuthenticated
    case sessionExpired
    case tooManyAttempts
    case networkError(Error)
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .emailAlreadyExists:
            return "An account with this email already exists"
        case .invalidEmail:
            return "Please enter a valid email address"
        case .weakPassword:
            return "Password must be at least 8 characters"
        case .notAuthenticated:
            return "Please log in to continue"
        case .sessionExpired:
            return "Your session has expired. Please log in again"
        case .tooManyAttempts:
            return "Too many attempts. Please try again later"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return message
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - API Response

struct APIErrorResponse: Codable {
    let code: String
    let message: String
}

// MARK: - JSON Decoder Extension

extension JSONDecoder {
    static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
