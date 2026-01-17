import SwiftUI
import AuthenticationServices

/// Main authentication view with Login/Register tabs
struct AuthView: View {
    @State private var viewModel: AuthViewModel
    @State private var selectedTab: AuthTab = .login
    @Environment(\.dismiss) private var dismiss

    init(authService: AuthService) {
        _viewModel = State(initialValue: AuthViewModel(authService: authService))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Logo
                    VStack(spacing: 8) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue.gradient)

                        Text("LiDAR Scanner")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 20)

                    // Tab Picker
                    Picker("Auth Mode", selection: $selectedTab) {
                        Text("Login").tag(AuthTab.login)
                        Text("Register").tag(AuthTab.register)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Form
                    VStack(spacing: 16) {
                        if selectedTab == .register {
                            TextField("Name (optional)", text: $viewModel.displayName)
                                .textFieldStyle(.authTextField)
                                .textContentType(.name)
                        }

                        TextField("Email", text: $viewModel.email)
                            .textFieldStyle(.authTextField)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)

                        SecureField("Password", text: $viewModel.password)
                            .textFieldStyle(.authTextField)
                            .textContentType(selectedTab == .login ? .password : .newPassword)

                        if selectedTab == .register {
                            SecureField("Confirm Password", text: $viewModel.confirmPassword)
                                .textFieldStyle(.authTextField)
                                .textContentType(.newPassword)
                        }
                    }
                    .padding(.horizontal)

                    // Error message
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Submit Button
                    Button(action: {
                        Task {
                            if selectedTab == .login {
                                await viewModel.login()
                            } else {
                                await viewModel.register()
                            }
                            if viewModel.isSuccess {
                                dismiss()
                            }
                        }
                    }) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(selectedTab == .login ? "Log In" : "Create Account")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(viewModel.isLoading || !viewModel.isFormValid(for: selectedTab))
                    .opacity(viewModel.isFormValid(for: selectedTab) ? 1 : 0.6)
                    .padding(.horizontal)

                    // Forgot Password
                    if selectedTab == .login {
                        Button("Forgot Password?") {
                            viewModel.showForgotPassword = true
                        }
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    }

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal)

                    // Sign in with Apple
                    SignInWithAppleButton(
                        onRequest: { request in
                            request.requestedScopes = [.email, .fullName]
                        },
                        onCompletion: { result in
                            Task {
                                await viewModel.handleAppleSignIn(result)
                                if viewModel.isSuccess {
                                    dismiss()
                                }
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // Terms
                    Text("By continuing, you agree to our [Terms of Service](https://lidarapp.com/terms) and [Privacy Policy](https://lidarapp.com/privacy)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $viewModel.showForgotPassword) {
                ForgotPasswordView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Auth Tab

enum AuthTab {
    case login
    case register
}

// MARK: - Forgot Password View

struct ForgotPasswordView: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Reset Password")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Enter your email and we'll send you a link to reset your password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Email", text: $viewModel.resetEmail)
                    .textFieldStyle(.authTextField)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                if viewModel.resetEmailSent {
                    Label("Reset link sent! Check your email.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }

                Button(action: {
                    Task {
                        await viewModel.requestPasswordReset()
                    }
                }) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Send Reset Link")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.isLoading || viewModel.resetEmail.isEmpty)

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Auth TextField Style

struct AuthTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension TextFieldStyle where Self == AuthTextFieldStyle {
    static var authTextField: AuthTextFieldStyle { AuthTextFieldStyle() }
}

// MARK: - Preview

#Preview {
    AuthView(authService: AuthService())
}
