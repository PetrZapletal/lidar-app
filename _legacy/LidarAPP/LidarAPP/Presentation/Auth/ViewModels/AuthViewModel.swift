import SwiftUI
import AuthenticationServices

/// ViewModel for authentication views
@MainActor
@Observable
final class AuthViewModel {

    // MARK: - Form State

    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var displayName: String = ""

    // Password Reset
    var resetEmail: String = ""
    var resetEmailSent: Bool = false
    var showForgotPassword: Bool = false

    // UI State
    var isLoading: Bool = false
    var isSuccess: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let authService: AuthService

    // MARK: - Initialization

    init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - Validation

    func isFormValid(for tab: AuthTab) -> Bool {
        switch tab {
        case .login:
            return isValidEmail(email) && password.count >= 6
        case .register:
            return isValidEmail(email) &&
                   password.count >= 8 &&
                   password == confirmPassword
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    var passwordStrength: PasswordStrength {
        let length = password.count
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasNumber = password.contains(where: { $0.isNumber })
        let hasSpecial = password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) })

        var score = 0
        if length >= 8 { score += 1 }
        if length >= 12 { score += 1 }
        if hasUppercase { score += 1 }
        if hasLowercase { score += 1 }
        if hasNumber { score += 1 }
        if hasSpecial { score += 1 }

        switch score {
        case 0...2: return .weak
        case 3...4: return .medium
        default: return .strong
        }
    }

    // MARK: - Actions

    func login() async {
        guard isFormValid(for: .login) else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.login(email: email, password: password)
            isSuccess = true
            clearForm()
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "An unexpected error occurred"
        }
    }

    func register() async {
        guard isFormValid(for: .register) else { return }

        if password != confirmPassword {
            errorMessage = "Passwords do not match"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.register(
                email: email,
                password: password,
                displayName: displayName.isEmpty ? nil : displayName
            )
            isSuccess = true
            clearForm()
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "An unexpected error occurred"
        }
    }

    func requestPasswordReset() async {
        guard isValidEmail(resetEmail) else {
            errorMessage = "Please enter a valid email"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.requestPasswordReset(email: resetEmail)
            resetEmailSent = true
        } catch {
            errorMessage = "Failed to send reset email"
        }
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = appleIDCredential.identityToken,
                  let identityTokenString = String(data: identityToken, encoding: .utf8),
                  let authorizationCode = appleIDCredential.authorizationCode,
                  let authorizationCodeString = String(data: authorizationCode, encoding: .utf8) else {
                errorMessage = "Failed to get Apple credentials"
                return
            }

            do {
                try await authService.loginWithApple(
                    identityToken: identityTokenString,
                    authorizationCode: authorizationCodeString
                )
                isSuccess = true
            } catch let error as AuthError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Apple Sign In failed"
            }

        case .failure(let error):
            // User cancelled or other error
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = "Apple Sign In failed"
            }
        }
    }

    // MARK: - Helpers

    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        displayName = ""
    }
}

// MARK: - Password Strength

enum PasswordStrength {
    case weak
    case medium
    case strong

    var color: Color {
        switch self {
        case .weak: return .red
        case .medium: return .orange
        case .strong: return .green
        }
    }

    var text: String {
        switch self {
        case .weak: return "Weak"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}
