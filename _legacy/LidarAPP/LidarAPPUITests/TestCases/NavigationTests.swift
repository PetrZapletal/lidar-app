import XCTest

/// Tests for navigation between screens.
final class NavigationTests: BaseUITestCase {

    // MARK: - Tab Navigation Tests

    /// Test navigation to Profile tab.
    func testNavigateToProfileTab() throws {
        // GIVEN: App is on Gallery tab
        let tabBar = TabBarPage(app: app)
        _ = tabBar.waitForDisplay() 

        // WHEN: Tap Profile tab
        let profile = tabBar.tapProfile()

        // THEN: Profile view should be displayed
        XCTAssertTrue(profile.waitForDisplay(), "Profile view should be displayed")
    }

    /// Test navigation back to Gallery from Profile.
    func testNavigateFromProfileToGallery() throws {
        // GIVEN: App is on Profile tab
        let tabBar = TabBarPage(app: app)
        _ = tabBar.tapProfile()

        // WHEN: Tap Gallery tab
        let gallery = tabBar.tapGallery()

        // THEN: Gallery view should be displayed
        XCTAssertTrue(gallery.waitForDisplay(), "Gallery view should be displayed")
    }

    /// Test that capture button opens scan mode selector.
    func testCaptureButtonOpensScanModeSelector() throws {
        // GIVEN: App is on Gallery tab
        let tabBar = TabBarPage(app: app)
        _ = tabBar.waitForDisplay() 

        // WHEN: Tap capture button
        let scanSelector = tabBar.tapCapture()

        // THEN: Scan mode selector should appear
        XCTAssertTrue(scanSelector.waitForDisplay(), "Scan mode selector should be displayed")
    }

    /// Test canceling scan mode selector returns to previous view.
    func testCancelScanModeSelector() throws {
        // GIVEN: Scan mode selector is open
        let tabBar = TabBarPage(app: app)
        let scanSelector = tabBar.tapCapture()
        _ = scanSelector.waitForDisplay() 

        // WHEN: Cancel
        let returnedTabBar = scanSelector.cancel()

        // THEN: Should return to tab bar view
        XCTAssertTrue(returnedTabBar.waitForDisplay(), "Should return to main view after cancel")
    }

    /// Test swipe down dismisses scan mode selector.
    func testSwipeDownDismissesScanModeSelector() throws {
        // GIVEN: Scan mode selector is open
        let tabBar = TabBarPage(app: app)
        let scanSelector = tabBar.tapCapture()
        _ = scanSelector.waitForDisplay() 

        // WHEN: Swipe down to dismiss
        let returnedTabBar = scanSelector.swipeDownToDismiss()

        // Wait a moment for animation
        sleep(1)

        // THEN: Should return to tab bar view
        XCTAssertTrue(returnedTabBar.waitForDisplay(), "Should return to main view after swipe down")
    }

    // MARK: - Settings Navigation Tests

    /// Test opening Settings from Profile.
    func testOpenSettingsFromProfile() throws {
        // GIVEN: App is on Profile tab
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        _ = profile.waitForDisplay() 

        // WHEN: Tap Settings
        let settings = profile.tapSettings()

        // THEN: Settings view should be displayed
        XCTAssertTrue(settings.waitForDisplay(), "Settings view should be displayed")
    }

    /// Test dismissing Settings returns to Profile.
    func testDismissSettingsReturnsToProfile() throws {
        // GIVEN: Settings is open
        let tabBar = TabBarPage(app: app)
        let profile = tabBar.tapProfile()
        let settings = profile.tapSettings()
        _ = settings.waitForDisplay() 

        // WHEN: Dismiss settings
        let returnedProfile = settings.dismiss()

        // THEN: Profile view should be displayed
        XCTAssertTrue(returnedProfile.waitForDisplay(), "Profile view should be displayed after dismissing settings")
    }

    // MARK: - Scan Mode Selection Tests

    /// Test all scan mode cards are visible.
    func testAllScanModesAreVisible() throws {
        // GIVEN: Scan mode selector is open
        let tabBar = TabBarPage(app: app)
        let scanSelector = tabBar.tapCapture()

        // THEN: All mode cards should be visible
        XCTAssertTrue(scanSelector.verifyAllModesPresent(), "All scan mode cards should be visible")
    }

    /// Test exterior mode card is interactive.
    func testExteriorModeCardIsInteractive() throws {
        // GIVEN: Scan mode selector is open
        let tabBar = TabBarPage(app: app)
        let scanSelector = tabBar.tapCapture()
        _ = scanSelector.waitForDisplay() 

        // THEN: Exterior card should be available (in mock mode)
        XCTAssertTrue(
            scanSelector.exteriorCard.exists,
            "Exterior mode card should exist"
        )
    }

    /// Test interior mode card is interactive.
    func testInteriorModeCardIsInteractive() throws {
        // GIVEN: Scan mode selector is open
        let tabBar = TabBarPage(app: app)
        let scanSelector = tabBar.tapCapture()
        _ = scanSelector.waitForDisplay() 

        // THEN: Interior card should exist
        XCTAssertTrue(
            scanSelector.interiorCard.exists,
            "Interior mode card should exist"
        )
    }

    /// Test object mode card is interactive.
    func testObjectModeCardIsInteractive() throws {
        // GIVEN: Scan mode selector is open
        let tabBar = TabBarPage(app: app)
        let scanSelector = tabBar.tapCapture()
        _ = scanSelector.waitForDisplay() 

        // THEN: Object card should exist
        XCTAssertTrue(
            scanSelector.objectCard.exists,
            "Object mode card should exist"
        )
    }

    // MARK: - Deep Navigation Tests

    /// Test navigation through multiple screens and back.
    func testDeepNavigationAndBack() throws {
        // GIVEN: App is launched
        let tabBar = TabBarPage(app: app)

        // WHEN: Navigate Gallery -> Profile -> Settings -> Back -> Back
        let profile = tabBar.tapProfile()
        XCTAssertTrue(profile.waitForDisplay())

        let settings = profile.tapSettings()
        XCTAssertTrue(settings.waitForDisplay())

        let returnedProfile = settings.dismiss()
        XCTAssertTrue(returnedProfile.waitForDisplay())

        let gallery = tabBar.tapGallery()
        XCTAssertTrue(gallery.waitForDisplay())

        // THEN: Should be back at Gallery
        XCTAssertTrue(gallery.isDisplayed(), "Should be back at Gallery")
    }
}
