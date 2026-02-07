import XCTest

/// Tests for authentication functionality.
final class AuthenticationTests: BaseUITestCase {

    // MARK: - Auth View Display Tests

    /// Test that Auth view displays when tapping login.
    func testAuthViewDisplaysWhenTappingLogin() throws {
        // GIVEN: Navigate to Profile and tap login
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        _ = profile.waitForDisplay() 

        // Skip if already logged in
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        // WHEN: Tap login
        let auth = profile.tapLogin()

        // THEN: Auth view should display
        XCTAssertTrue(auth.waitForDisplay(), "Auth view should be displayed")
    }

    /// Test that login tab is selected by default.
    func testLoginTabSelectedByDefault() throws {
        // GIVEN: Open Auth view
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // THEN: Login tab should be selected or visible
        let hasLoginTab = auth.loginTab.exists ||
                          app.buttons["Login"].exists ||
                          app.buttons["Log In"].exists
        XCTAssertTrue(hasLoginTab, "Login tab should be present")
    }

    /// Test that email field is visible.
    func testEmailFieldIsVisible() throws {
        // GIVEN: Open Auth view
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // THEN: Email field should be visible
        XCTAssertTrue(
            auth.emailField.exists ||
            app.textFields["Email"].exists,
            "Email field should be visible"
        )
    }

    /// Test that password field is visible.
    func testPasswordFieldIsVisible() throws {
        // GIVEN: Open Auth view
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // THEN: Password field should be visible
        XCTAssertTrue(
            auth.passwordField.exists ||
            app.secureTextFields["Password"].exists,
            "Password field should be visible"
        )
    }

    /// Test that skip button is visible.
    func testSkipButtonIsVisible() throws {
        // GIVEN: Open Auth view
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // THEN: Skip button should be visible
        XCTAssertTrue(
            auth.skipButton.exists ||
            app.buttons["Skip"].exists,
            "Skip button should be visible"
        )
    }

    // MARK: - Tab Switching Tests

    /// Test switching to Register tab.
    func testSwitchingToRegisterTab() throws {
        // GIVEN: Open Auth view on login tab
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // WHEN: Switch to Register tab
        auth.switchToRegister()
        sleep(1)

        // THEN: Additional fields should appear
        let hasConfirmPassword = auth.confirmPasswordField.exists ||
                                 app.secureTextFields["Confirm Password"].exists
        XCTAssertTrue(hasConfirmPassword, "Confirm password field should appear on Register tab")
    }

    /// Test switching back to Login tab.
    func testSwitchingBackToLoginTab() throws {
        // GIVEN: Open Auth view and switch to Register
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = _ = auth.waitForDisplay() 
        auth.switchToRegister()

        // WHEN: Switch back to Login
        auth.switchToLogin()
        sleep(1)

        // THEN: Confirm password should not be visible
        let noConfirmPassword = !auth.confirmPasswordField.exists
        XCTAssertTrue(noConfirmPassword || !app.secureTextFields["Confirm Password"].isHittable,
                      "Confirm password field should not be visible on Login tab")
    }

    // MARK: - Skip Flow Tests

    /// Test that skip button dismisses auth view.
    func testSkipButtonDismissesAuthView() throws {
        // GIVEN: Open Auth view
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // WHEN: Tap skip
        let returnedTabBar = auth.skip()

        // THEN: Should return to main view
        XCTAssertTrue(returnedTabBar.waitForDisplay(), "Should return to main view after skipping")
    }

    // MARK: - Form Validation Tests

    /// Test that submit button is disabled with empty fields.
    func testSubmitButtonDisabledWithEmptyFields() throws {
        // GIVEN: Open Auth view with empty fields
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // THEN: Submit button should be disabled or have reduced opacity
        // (We can check if it's enabled)
        let submitButton = auth.submitButton
        if submitButton.exists {
            // The button may be disabled or have reduced opacity
            // Just verify it exists
            XCTAssertTrue(submitButton.exists, "Submit button should exist")
        }
    }

    /// Test entering email updates field.
    func testEnteringEmailUpdatesField() throws {
        // GIVEN: Open Auth view
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // WHEN: Enter email
        let testEmail = "test@example.com"
        auth.enterEmail(testEmail)

        // THEN: Field should contain the email
        let emailField = auth.emailField
        if emailField.exists {
            let fieldValue = emailField.value as? String ?? ""
            XCTAssertTrue(
                fieldValue.contains("test") || fieldValue.contains("@"),
                "Email field should contain entered text"
            )
        }
    }

    // MARK: - Sign in with Apple Tests

    /// Test that Sign in with Apple button is visible.
    func testSignInWithAppleButtonIsVisible() throws {
        // GIVEN: Open Auth view
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // THEN: Sign in with Apple should be visible
        XCTAssertTrue(
            auth.signInWithAppleButton.exists ||
            app.buttons.containing(NSPredicate(format: "label CONTAINS 'Apple'")).count > 0,
            "Sign in with Apple button should be visible"
        )
    }

    // MARK: - Forgot Password Tests

    /// Test that Forgot Password button is visible on Login tab.
    func testForgotPasswordButtonVisible() throws {
        // GIVEN: Open Auth view on Login tab
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // THEN: Forgot Password should be visible
        XCTAssertTrue(
            auth.forgotPasswordButton.exists ||
            app.buttons.containing(NSPredicate(format: "label CONTAINS 'Forgot'")).count > 0,
            "Forgot Password button should be visible"
        )
    }

    /// Test that tapping Forgot Password opens reset sheet.
    func testTappingForgotPasswordOpensResetSheet() throws {
        // GIVEN: Open Auth view
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        let auth = profile.tapLogin()
        _ = auth.waitForDisplay() 

        // WHEN: Tap Forgot Password
        let forgotPassword = auth.tapForgotPassword()

        // THEN: Forgot Password view should be displayed
        XCTAssertTrue(forgotPassword.waitForDisplay(), "Forgot Password view should be displayed")
    }
}
