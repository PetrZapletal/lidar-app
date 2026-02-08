import XCTest

/// Page Object for the Authentication view (Login/Register).
final class AuthPage: BasePage {

    // MARK: - Elements

    /// App logo
    var logo: XCUIElement {
        app.images["cube.transparent"].firstMatch
    }

    /// Login tab in segmented control
    var loginTab: XCUIElement {
        app.buttons["Login"].firstMatch
    }

    /// Register tab in segmented control
    var registerTab: XCUIElement {
        app.buttons["Register"].firstMatch
    }

    /// Email text field
    var emailField: XCUIElement {
        let identified = app.textFields[AccessibilityIdentifiers.Auth.emailField]
        if identified.exists { return identified }

        return app.textFields["Email"].firstMatch
    }

    /// Password secure field
    var passwordField: XCUIElement {
        let identified = app.secureTextFields[AccessibilityIdentifiers.Auth.passwordField]
        if identified.exists { return identified }

        return app.secureTextFields["Password"].firstMatch
    }

    /// Confirm password field (Register only)
    var confirmPasswordField: XCUIElement {
        app.secureTextFields["Confirm Password"].firstMatch
    }

    /// Name field (Register only)
    var nameField: XCUIElement {
        app.textFields["Name (optional)"].firstMatch
    }

    /// Submit button (Log In / Create Account)
    var submitButton: XCUIElement {
        let loginButton = app.buttons["Log In"]
        if loginButton.exists { return loginButton }

        return app.buttons["Create Account"].firstMatch
    }

    /// Forgot password button
    var forgotPasswordButton: XCUIElement {
        app.buttons["Forgot Password?"].firstMatch
    }

    /// Sign in with Apple button
    var signInWithAppleButton: XCUIElement {
        app.buttons["Sign in with Apple"].firstMatch
    }

    /// Skip button
    var skipButton: XCUIElement {
        app.buttons["Skip"].firstMatch
    }

    /// Error message label
    var errorMessage: XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Auth.errorMessage].firstMatch
    }

    /// Loading indicator on submit button
    var submitLoadingIndicator: XCUIElement {
        submitButton.activityIndicators.firstMatch
    }

    // MARK: - Computed Properties

    /// Check if currently on login tab
    var isOnLoginTab: Bool {
        loginTab.isSelected
    }

    /// Check if currently on register tab
    var isOnRegisterTab: Bool {
        registerTab.isSelected
    }

    /// Check if submit button is enabled
    var isSubmitEnabled: Bool {
        submitButton.isEnabled
    }

    /// Check if loading
    override var isLoading: Bool {
        submitLoadingIndicator.exists
    }

    /// Check if error is displayed
    var hasError: Bool {
        errorMessage.exists
    }

    /// Get error message text
    var errorText: String? {
        guard hasError else { return nil }
        return errorMessage.label
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return emailField.waitForExistence(timeout: 5) ||
               loginTab.exists ||
               skipButton.exists
    }

    // MARK: - Tab Actions

    /// Switch to login tab
    @discardableResult
    func switchToLogin() -> Self {
        if !isOnLoginTab {
            waitAndTap(loginTab)
        }
        return self
    }

    /// Switch to register tab
    @discardableResult
    func switchToRegister() -> Self {
        if !isOnRegisterTab {
            waitAndTap(registerTab)
        }
        return self
    }

    // MARK: - Form Actions

    /// Enter email
    @discardableResult
    func enterEmail(_ email: String) -> Self {
        typeText(email, in: emailField)
        return self
    }

    /// Enter password
    @discardableResult
    func enterPassword(_ password: String) -> Self {
        typeText(password, in: passwordField)
        return self
    }

    /// Enter confirm password
    @discardableResult
    func enterConfirmPassword(_ password: String) -> Self {
        typeText(password, in: confirmPasswordField)
        return self
    }

    /// Enter name
    @discardableResult
    func enterName(_ name: String) -> Self {
        typeText(name, in: nameField)
        return self
    }

    /// Tap submit button
    @discardableResult
    func tapSubmit() -> Self {
        waitAndTap(submitButton)
        return self
    }

    /// Tap skip button
    @discardableResult
    func skip() -> TabBarPage {
        waitAndTap(skipButton)
        return TabBarPage(app: app)
    }

    // MARK: - Login Flow

    /// Perform login with email and password
    @discardableResult
    func login(email: String, password: String) -> Self {
        switchToLogin()
        enterEmail(email)
        enterPassword(password)
        tapSubmit()
        return self
    }

    /// Wait for login to complete (success or error)
    @discardableResult
    func waitForLoginResult(timeout: TimeInterval = 10) -> Self {
        // Wait for either error message or navigation away
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if hasError || !isDisplayed() {
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return self
    }

    // MARK: - Register Flow

    /// Perform registration with all fields
    @discardableResult
    func register(name: String = "", email: String, password: String, confirmPassword: String) -> Self {
        switchToRegister()
        if !name.isEmpty {
            enterName(name)
        }
        enterEmail(email)
        enterPassword(password)
        enterConfirmPassword(confirmPassword)
        tapSubmit()
        return self
    }

    // MARK: - Forgot Password Flow

    /// Open forgot password sheet
    @discardableResult
    func tapForgotPassword() -> ForgotPasswordPage {
        waitAndTap(forgotPasswordButton)
        return ForgotPasswordPage(app: app)
    }

    // MARK: - Sign in with Apple

    /// Tap Sign in with Apple button
    @discardableResult
    func tapSignInWithApple() -> Self {
        waitAndTap(signInWithAppleButton)
        return self
    }
}

/// Page Object for the Forgot Password sheet.
final class ForgotPasswordPage: BasePage {

    // MARK: - Elements

    /// Email field
    var emailField: XCUIElement {
        app.textFields["Email"].firstMatch
    }

    /// Send reset link button
    var sendButton: XCUIElement {
        app.buttons["Send Reset Link"].firstMatch
    }

    /// Cancel button
    var cancelButton: XCUIElement {
        app.buttons["Cancel"].firstMatch
    }

    /// Success message
    var successMessage: XCUIElement {
        app.staticTexts["Reset link sent! Check your email."].firstMatch
    }

    // MARK: - Computed Properties

    /// Check if reset was successful
    var isResetSuccessful: Bool {
        successMessage.exists
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return emailField.waitForExistence(timeout: 5) ||
               sendButton.exists
    }

    // MARK: - Actions

    /// Request password reset
    @discardableResult
    func requestReset(email: String) -> Self {
        typeText(email, in: emailField)
        waitAndTap(sendButton)
        return self
    }

    /// Cancel and close
    @discardableResult
    func cancel() -> AuthPage {
        waitAndTap(cancelButton)
        return AuthPage(app: app)
    }

    /// Wait for reset result
    @discardableResult
    func waitForResult(timeout: TimeInterval = 10) -> Self {
        _ = successMessage.waitForExistence(timeout: timeout)
        return self
    }
}
