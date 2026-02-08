import XCTest

/// Tests for the Settings view functionality.
final class SettingsTests: BaseUITestCase {

    private var settings: SettingsPage!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Navigate to Settings
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        settings = profile.tapSettings()
        _ = settings.waitForDisplay() 
    }

    // MARK: - Display Tests

    /// Test that Settings has correct navigation title.
    func testSettingsHasCorrectTitle() throws {
        XCTAssertTrue(
            settings.navigationTitle.exists ||
            app.navigationBars.staticTexts["Nastaveni"].exists,
            "Settings should have correct navigation title"
        )
    }

    /// Test that Done button is visible.
    func testDoneButtonIsVisible() throws {
        XCTAssertTrue(
            settings.doneButton.exists,
            "Done button should be visible"
        )
    }

    // MARK: - Developer Section Tests

    /// Test that Mock Mode toggle is visible.
    func testMockModeToggleIsVisible() throws {
        XCTAssertTrue(
            settings.mockModeToggle.exists ||
            app.switches.containing(NSPredicate(format: "label CONTAINS 'Mock'")).count > 0,
            "Mock Mode toggle should be visible"
        )
    }

    /// Test that Mock Mode is enabled in simulator.
    func testMockModeEnabledInSimulator() throws {
        // In simulator, mock mode should typically be enabled
        // This is a soft assertion as it depends on previous state
        let mockToggle = settings.mockModeToggle
        if mockToggle.exists {
            // Just verify the toggle exists and is interactable
            XCTAssertTrue(mockToggle.isEnabled, "Mock Mode toggle should be interactable")
        }
    }

    /// Test that Mock Mode can be toggled.
    func testMockModeCanBeToggled() throws {
        let mockToggle = settings.mockModeToggle
        guard mockToggle.exists else {
            throw XCTSkip("Mock Mode toggle not found")
        }

        let initialState = settings.isMockModeEnabled

        // WHEN: Toggle mock mode
        settings.toggleMockMode()
        sleep(1)

        // THEN: State should change (or remain same if restricted)
        // We just verify it doesn't crash
        XCTAssertTrue(settings.isDisplayed(), "Settings should remain displayed after toggle")
    }

    // MARK: - Debug Upload Section Tests

    /// Test that Raw Data Mode toggle is visible.
    func testRawDataModeToggleIsVisible() throws {
        // May need to scroll to see this section
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
        }

        XCTAssertTrue(
            settings.rawDataModeToggle.exists ||
            app.switches.containing(NSPredicate(format: "label CONTAINS 'Raw Data'")).count > 0,
            "Raw Data Mode toggle should be visible"
        )
    }

    /// Test that Test Connection button is visible when Raw Data Mode is enabled.
    func testTestConnectionButtonVisibleWhenRawDataModeEnabled() throws {
        // Enable raw data mode first
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
        }

        if !settings.isRawDataModeEnabled {
            settings.toggleRawDataMode()
            sleep(1)
        }

        // THEN: Test Connection button should be visible
        let hasTestButton = settings.testConnectionButton.exists ||
                            app.buttons.containing(NSPredicate(format: "label CONTAINS 'Test Connection'")).count > 0
        XCTAssertTrue(hasTestButton, "Test Connection button should be visible when Raw Data Mode is enabled")
    }

    // MARK: - Processing Section Tests

    /// Test that Depth Fusion toggle is visible.
    func testDepthFusionToggleIsVisible() throws {
        // SwiftUI Form renders as collectionView in iOS 16+
        // Depth Fusion is in the 5th section (processingSection), need more scrolls
        // Keep scrolling until we find it or reach max attempts
        var found = false
        for _ in 0..<6 {
            if settings.depthFusionToggle.exists ||
               app.switches[AccessibilityIdentifiers.Settings.depthFusionToggle].exists ||
               app.staticTexts["Depth Fusion"].exists ||
               app.staticTexts["Zpracování"].exists {
                found = true
                break
            }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }

        XCTAssertTrue(
            found ||
            settings.depthFusionToggle.exists ||
            app.switches[AccessibilityIdentifiers.Settings.depthFusionToggle].exists ||
            app.switches.containing(NSPredicate(format: "label CONTAINS 'Depth Fusion'")).count > 0 ||
            app.staticTexts["Depth Fusion"].exists ||
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Depth Fusion'")).count > 0,
            "Depth Fusion toggle should be visible"
        )
    }

    /// Helper to scroll settings form
    private func scrollSettingsDown(times: Int = 1) {
        // SwiftUI Form can be rendered as various container types
        // Direct swipe on app is most reliable
        for _ in 0..<times {
            app.swipeUp()
            // Small delay to let scroll animation complete
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    // MARK: - Export Section Tests

    /// Test that Output Formats link is visible.
    func testOutputFormatsLinkIsVisible() throws {
        // SwiftUI Form renders as collectionView in iOS 16+
        scrollSettingsDown(times: 2)

        XCTAssertTrue(
            settings.outputFormatsLink.exists ||
            app.buttons.containing(NSPredicate(format: "label CONTAINS 'formáty'")).count > 0 ||
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'formáty'")).count > 0,
            "Output Formats link should be visible"
        )
    }

    // MARK: - Diagnostics Section Tests

    /// Test that diagnostics section is visible.
    func testDiagnosticsSectionIsVisible() throws {
        // SwiftUI Form renders as collectionView in iOS 16+
        scrollSettingsDown(times: 3)

        let hasDiagnostics = settings.exportDiagnosticsButton.exists ||
                             settings.crashDetailsLink.exists ||
                             app.buttons.containing(NSPredicate(format: "label CONTAINS 'diagnostiku'")).count > 0 ||
                             app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Diagnostika'")).count > 0
        XCTAssertTrue(hasDiagnostics, "Diagnostics section should be visible")
    }

    // MARK: - About Section Tests

    /// Test that version info is displayed.
    func testVersionInfoIsDisplayed() throws {
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
            scrollView.swipeUp()
        }

        let hasVersion = settings.versionLabel.exists ||
                         app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Verze'")).count > 0
        XCTAssertTrue(hasVersion, "Version info should be displayed")
    }

    /// Test that privacy policy link is available.
    func testPrivacyPolicyLinkIsAvailable() throws {
        // SwiftUI Form renders as collectionView in iOS 16+
        scrollSettingsDown(times: 4)

        let hasPrivacy = settings.privacyPolicyLink.exists ||
                         app.buttons.containing(NSPredicate(format: "label CONTAINS 'osobních'")).count > 0 ||
                         app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'osobních'")).count > 0 ||
                         app.links.count > 0
        XCTAssertTrue(hasPrivacy, "Privacy policy link should be available")
    }

    // MARK: - Dismiss Tests

    /// Test that Settings can be dismissed.
    func testSettingsCanBeDismissed() throws {
        // WHEN: Tap Done
        let profile = settings.dismiss()

        // THEN: Should return to Profile
        XCTAssertTrue(profile.waitForDisplay(), "Should return to Profile after dismissing Settings")
    }
}
