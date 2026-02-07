import XCTest

/// Tests for the Profile view functionality.
final class ProfileTests: BaseUITestCase {

    // MARK: - Display Tests

    /// Test that Profile has correct navigation title.
    func testProfileHasCorrectTitle() throws {
        // GIVEN: Navigate to Profile
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()

        // THEN: Navigation title should be correct
        XCTAssertTrue(
            profile.navigationTitle.waitForExistence(timeout: 5) ||
            app.navigationBars.staticTexts["Profil"].exists,
            "Profile should have correct navigation title"
        )
    }

    /// Test that Settings button is visible.
    func testSettingsButtonIsVisible() throws {
        // GIVEN: Navigate to Profile
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        _ = profile.waitForDisplay() 

        // THEN: Settings button should be visible
        XCTAssertTrue(
            profile.settingsButton.exists ||
            app.buttons.containing(NSPredicate(format: "label CONTAINS 'Nastaveni'")).count > 0,
            "Settings button should be visible"
        )
    }

    /// Test that Help button is visible.
    func testHelpButtonIsVisible() throws {
        // GIVEN: Navigate to Profile
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        _ = profile.waitForDisplay() 

        // THEN: Help button should be visible
        let hasHelp = profile.helpButton.exists ||
                      app.buttons.containing(NSPredicate(format: "label CONTAINS 'Napoveda'")).count > 0
        XCTAssertTrue(hasHelp, "Help button should be visible")
    }

    /// Test that version info is displayed.
    func testVersionInfoIsDisplayed() throws {
        // GIVEN: Navigate to Profile
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        _ = profile.waitForDisplay() 

        // Scroll to find version info if needed
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
        }

        // THEN: Version info should be visible
        let hasVersion = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Verze'")).count > 0 ||
                         app.cells.containing(NSPredicate(format: "label CONTAINS 'Verze'")).count > 0
        XCTAssertTrue(hasVersion, "Version info should be displayed")
    }

    // MARK: - Login State Tests

    /// Test that login option is shown when not authenticated.
    func testLoginOptionShownWhenNotAuthenticated() throws {
        // GIVEN: Navigate to Profile (not logged in)
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        _ = profile.waitForDisplay() 

        // THEN: Should show login option or user info (if already logged in)
        let hasLoginOrUser = profile.loginButton.exists ||
                             profile.userNameLabel.exists ||
                             app.buttons.containing(NSPredicate(format: "label CONTAINS 'Prihlasit'")).count > 0
        XCTAssertTrue(hasLoginOrUser, "Should show login option or user info")
    }

    /// Test that tapping login opens auth view.
    func testTappingLoginOpensAuthView() throws {
        // GIVEN: Navigate to Profile (not logged in)
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        _ = profile.waitForDisplay() 

        // Skip if already logged in
        guard profile.isLoggedOut else {
            throw XCTSkip("User is already logged in")
        }

        // WHEN: Tap login
        let auth = profile.tapLogin()

        // THEN: Auth view should be displayed
        XCTAssertTrue(auth.waitForDisplay(), "Auth view should be displayed")
    }

    // MARK: - Settings Navigation Tests

    /// Test that Settings can be opened from Profile.
    func testSettingsCanBeOpened() throws {
        // GIVEN: Navigate to Profile
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        _ = profile.waitForDisplay() 

        // WHEN: Tap Settings
        let settings = profile.tapSettings()

        // THEN: Settings view should be displayed
        XCTAssertTrue(settings.waitForDisplay(), "Settings view should be displayed")
    }
}
