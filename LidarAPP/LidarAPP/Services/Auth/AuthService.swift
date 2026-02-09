import Foundation
import AuthenticationServices
import UIKit

// MARK: - Auth Service

/// Manages Sign in with Apple authentication and session persistence.
///
/// Uses `KeychainService` for secure token and user storage.
/// Conforms to `ASAuthorizationControllerDelegate` and
/// `ASAuthorizationControllerPresentationContextProviding`
/// to drive the Apple Sign In flow.
@MainActor
@Observable
final class AuthService: NSObject {

    // MARK: - Auth State

    enum AuthState: Sendable {
        case unknown
        case signedOut
        case signedIn(User)
    }

    // MARK: - Observable Properties

    private(set) var authState: AuthState = .unknown
    private(set) var isLoading: Bool = false

    // MARK: - Dependencies

    private let keychain: KeychainService

    // MARK: - Continuations

    /// Continuation used to bridge the delegate-based Apple Sign In
    /// into async/await.
    private var signInContinuation: CheckedContinuation<ASAuthorization, Error>?

    // MARK: - Keychain Keys (internal to AuthService)

    private enum Keys {
        static let identityToken = "apple_identity_token"
        static let authorizationCode = "apple_authorization_code"
        static let userIdentifier = "apple_user_identifier"
    }

    // MARK: - Initialization

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
        super.init()
        infoLog("AuthService initialized", category: .logCategoryNetwork)
    }

    // MARK: - Sign In with Apple

    /// Initiates the Apple Sign In flow.
    ///
    /// Presents the system sign-in sheet, processes the credential,
    /// stores tokens and user data in the Keychain, and updates `authState`.
    func signInWithApple() async throws {
        guard !isLoading else {
            warningLog("Sign in already in progress", category: .logCategoryNetwork)
            return
        }

        isLoading = true
        defer { isLoading = false }

        debugLog("Starting Apple Sign In flow", category: .logCategoryNetwork)

        do {
            let authorization = try await performAppleSignIn()
            try await handleAuthorization(authorization)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            debugLog("Apple Sign In cancelled by user", category: .logCategoryNetwork)
            throw AuthError.appleSignInCancelled
        } catch let error as AuthError {
            errorLog("Apple Sign In failed: \(error.localizedDescription)", category: .logCategoryNetwork)
            throw error
        } catch {
            errorLog("Apple Sign In unexpected error: \(error.localizedDescription)", category: .logCategoryNetwork)
            throw AuthError.appleSignInFailed(error.localizedDescription)
        }
    }

    /// Check whether a previously stored session is still valid.
    ///
    /// Loads the user identifier from the Keychain, then verifies its
    /// credential state with Apple's servers. On success, loads the full
    /// `User` object from the Keychain and sets `authState = .signedIn`.
    func checkExistingSession() async {
        debugLog("Checking existing session", category: .logCategoryNetwork)

        do {
            let userIdentifier = try await keychain.loadString(forKey: Keys.userIdentifier)

            let credentialState = try await getCredentialState(forUserID: userIdentifier)

            switch credentialState {
            case .authorized:
                let user = try await keychain.load(forKey: KeychainKey.currentUser, as: User.self)
                authState = .signedIn(user)
                infoLog("Existing session restored for user: \(user.name)", category: .logCategoryNetwork)

            case .revoked, .notFound:
                warningLog("Credential state: \(credentialState.rawValue) - signing out", category: .logCategoryNetwork)
                await signOut()

            case .transferred:
                warningLog("Credential transferred - signing out", category: .logCategoryNetwork)
                await signOut()

            @unknown default:
                warningLog("Unknown credential state - signing out", category: .logCategoryNetwork)
                await signOut()
            }
        } catch {
            debugLog("No existing session found: \(error.localizedDescription)", category: .logCategoryNetwork)
            authState = .signedOut
        }
    }

    /// Signs the user out by clearing all stored credentials.
    func signOut() async {
        debugLog("Signing out", category: .logCategoryNetwork)

        do {
            try await keychain.deleteAll()
            infoLog("Keychain cleared successfully", category: .logCategoryNetwork)
        } catch {
            errorLog("Failed to clear Keychain during sign out: \(error.localizedDescription)", category: .logCategoryNetwork)
        }

        authState = .signedOut
    }

    /// Returns the stored identity token, if available.
    func getAccessToken() async -> String? {
        do {
            let token = try await keychain.loadString(forKey: Keys.identityToken)
            return token
        } catch {
            debugLog("No access token available: \(error.localizedDescription)", category: .logCategoryNetwork)
            return nil
        }
    }

    /// Verifies that the stored credential is still valid and returns
    /// the identity token. If the credential has been revoked, throws
    /// `AuthError.tokenExpired`.
    func refreshTokenIfNeeded() async throws -> String {
        guard let userIdentifier = try? await keychain.loadString(forKey: Keys.userIdentifier) else {
            throw AuthError.notAuthenticated
        }

        let credentialState = try await getCredentialState(forUserID: userIdentifier)

        guard credentialState == .authorized else {
            warningLog("Credential no longer authorized during refresh", category: .logCategoryNetwork)
            await signOut()
            throw AuthError.tokenExpired
        }

        guard let token = await getAccessToken() else {
            throw AuthError.notAuthenticated
        }

        debugLog("Token validated successfully", category: .logCategoryNetwork)
        return token
    }

    // MARK: - Private Helpers

    /// Uses `CheckedContinuation` to bridge the delegate-based
    /// `ASAuthorizationController` into an async call.
    private func performAppleSignIn() async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation

            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    /// Processes a successful `ASAuthorization`, extracting the Apple ID
    /// credential and persisting it to the Keychain.
    private func handleAuthorization(_ authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.appleSignInFailed("Invalid credential type")
        }

        let userIdentifier = credential.user

        // Extract identity token
        var identityTokenString: String?
        if let tokenData = credential.identityToken,
           let tokenStr = String(data: tokenData, encoding: .utf8) {
            identityTokenString = tokenStr
        }

        // Extract authorization code
        var authorizationCodeString: String?
        if let codeData = credential.authorizationCode,
           let codeStr = String(data: codeData, encoding: .utf8) {
            authorizationCodeString = codeStr
        }

        // Build full name from name components (only provided on first sign-in)
        let fullName = buildFullName(from: credential.fullName)
        let email = credential.email

        // Build the User model
        // On subsequent sign-ins Apple does not return name/email, so we
        // try loading the previously stored user and merging data.
        let user = await buildUser(
            userIdentifier: userIdentifier,
            email: email,
            fullName: fullName,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName
        )

        // Persist to Keychain
        do {
            try await keychain.save(userIdentifier, forKey: Keys.userIdentifier)
            try await keychain.save(user, forKey: KeychainKey.currentUser)

            if let token = identityTokenString {
                try await keychain.save(token, forKey: Keys.identityToken)
            }

            if let code = authorizationCodeString {
                try await keychain.save(code, forKey: Keys.authorizationCode)
            }

            infoLog("Credentials stored for user: \(user.name)", category: .logCategoryNetwork)
        } catch {
            errorLog("Failed to store credentials: \(error.localizedDescription)", category: .logCategoryNetwork)
            throw AuthError.keychainError(error.localizedDescription)
        }

        authState = .signedIn(user)
        infoLog("Sign in successful for user: \(user.name)", category: .logCategoryNetwork)
    }

    /// Builds a display name from `PersonNameComponents`.
    private func buildFullName(from nameComponents: PersonNameComponents?) -> String? {
        guard let components = nameComponents else { return nil }
        var parts: [String] = []
        if let given = components.givenName { parts.append(given) }
        if let family = components.familyName { parts.append(family) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Constructs a `User` value, merging with previously stored data
    /// when Apple does not supply name/email on repeat sign-ins.
    private func buildUser(
        userIdentifier: String,
        email: String?,
        fullName: String?,
        givenName: String?,
        familyName: String?
    ) async -> User {
        // Try loading existing user for merge
        let existingUser = try? await keychain.load(forKey: KeychainKey.currentUser, as: User.self)

        let resolvedEmail = email ?? existingUser?.email ?? ""
        let resolvedDisplayName = fullName ?? existingUser?.displayName
        let resolvedCreatedAt = existingUser?.createdAt ?? Date()

        return User(
            id: userIdentifier,
            email: resolvedEmail,
            displayName: resolvedDisplayName,
            createdAt: resolvedCreatedAt
        )
    }

    /// Wraps `ASAuthorizationAppleIDProvider.getCredentialState` in async/await.
    private func getCredentialState(forUserID userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            signInContinuation?.resume(returning: authorization)
            signInContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            signInContinuation?.resume(throwing: error)
            signInContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthService: ASAuthorizationControllerPresentationContextProviding {

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Must dispatch to main thread to access UIApplication safely
        return MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            let window = windowScene?.windows.first(where: { $0.isKeyWindow })
            return window ?? ASPresentationAnchor()
        }
    }
}
