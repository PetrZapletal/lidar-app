import XCTest

/// Page Object for the Profile tab view.
final class ProfilePage: BasePage {

    // MARK: - Elements

    /// Navigation title
    var navigationTitle: XCUIElement {
        app.navigationBars["Profil"].firstMatch
    }

    /// Login button (when not logged in)
    var loginButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Profile.loginButton]
        if identified.exists { return identified }

        // Fallback
        return app.buttons["Prihlasit se"].firstMatch
    }

    /// Settings button
    var settingsButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Profile.settingsButton]
        if identified.exists { return identified }

        // Fallback
        return app.buttons["Nastaveni"].firstMatch
    }

    /// Help button
    var helpButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Profile.helpButton]
        if identified.exists { return identified }

        // Fallback: NavigationLink in List shows as cell/button
        let byLabel = app.buttons["Nápověda"].firstMatch
        if byLabel.exists { return byLabel }

        return app.staticTexts["Nápověda"].firstMatch
    }

    /// Website link
    var websiteLink: XCUIElement {
        app.buttons["Webove stranky"].firstMatch
    }

    /// Version label
    var versionLabel: XCUIElement {
        app.staticTexts.matching(identifier: AccessibilityIdentifiers.Profile.versionLabel).firstMatch
    }

    // MARK: - Logged In State Elements

    /// User avatar
    var userAvatar: XCUIElement {
        app.images[AccessibilityIdentifiers.Profile.userAvatar].firstMatch
    }

    /// User name label
    var userNameLabel: XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Profile.userNameLabel].firstMatch
    }

    /// User email label
    var userEmailLabel: XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Profile.userEmailLabel].firstMatch
    }

    /// Subscription badge
    var subscriptionBadge: XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Profile.subscriptionBadge].firstMatch
    }

    /// Logout button
    var logoutButton: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Profile.logoutButton].firstMatch
    }

    // MARK: - Statistics

    /// Total scans count
    var totalScansLabel: XCUIElement {
        app.staticTexts["Celkem skenu"].firstMatch
    }

    /// AI processed count
    var aiProcessedLabel: XCUIElement {
        app.staticTexts["Zpracovano AI"].firstMatch
    }

    // MARK: - Computed Properties

    /// Check if user is logged in
    var isLoggedIn: Bool {
        !loginButton.exists && userNameLabel.exists
    }

    /// Check if user is logged out
    var isLoggedOut: Bool {
        loginButton.exists
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return navigationTitle.exists ||
               app.navigationBars.staticTexts["Profil"].exists ||
               loginButton.exists ||
               settingsButton.exists
    }

    // MARK: - Actions

    /// Tap login button to open authentication
    @discardableResult
    func tapLogin() -> AuthPage {
        waitAndTap(loginButton)
        return AuthPage(app: app)
    }

    /// Tap settings button to open settings
    @discardableResult
    func tapSettings() -> SettingsPage {
        waitAndTap(settingsButton)
        return SettingsPage(app: app)
    }

    /// Tap help button
    @discardableResult
    func tapHelp() -> Self {
        waitAndTap(helpButton)
        return self
    }

    /// Tap logout button (when logged in)
    @discardableResult
    func tapLogout() -> Self {
        if waitFor(logoutButton) {
            logoutButton.tap()
        }
        return self
    }

    /// Confirm logout in dialog
    @discardableResult
    func confirmLogout() -> Self {
        // Handle confirmation dialog
        let logoutConfirmButton = app.buttons["Log Out"]
        if waitFor(logoutConfirmButton, timeout: 5) {
            logoutConfirmButton.tap()
        }
        return self
    }

    /// Cancel logout in dialog
    @discardableResult
    func cancelLogout() -> Self {
        let cancelButton = app.buttons["Cancel"]
        if waitFor(cancelButton, timeout: 5) {
            cancelButton.tap()
        }
        return self
    }

    /// Get current app version from UI
    func getAppVersion() -> String? {
        // Find the version text in the list
        let versionCell = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Verze'")).firstMatch
        if versionCell.exists {
            return versionCell.label
        }
        return nil
    }
}
