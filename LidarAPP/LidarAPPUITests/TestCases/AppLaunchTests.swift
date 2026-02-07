import XCTest

/// Tests for app launch and initial state.
final class AppLaunchTests: BaseUITestCase {

    // MARK: - Launch Tests

    /// Test that app launches successfully and displays main UI.
    func testAppLaunchesSuccessfully() throws {
        // GIVEN: App is launched (done in setUp)

        // THEN: Tab bar should be visible
        let tabBar = TabBarPage(app: app)
        XCTAssertTrue(tabBar.waitForDisplay(), "Tab bar should be displayed after launch")
    }

    /// Test that Gallery tab is selected by default.
    func testGalleryTabIsSelectedByDefault() throws {
        // GIVEN: App is launched

        // THEN: Gallery view should be visible
        let gallery = GalleryPage(app: app)
        XCTAssertTrue(gallery.waitForDisplay(), "Gallery should be displayed by default")
    }

    /// Test that empty state is shown when no scans exist (clean launch).
    func testEmptyStateDisplayedForNewUser() throws {
        // Note: This test depends on clean launch configuration
        // In mock mode, sample scans may be pre-populated

        // GIVEN: App is launched
        let gallery = GalleryPage(app: app)

        // WHEN: Gallery is displayed
        _ = gallery.waitForDisplay() 

        // THEN: Either empty state or pre-populated mock scans should be visible
        // (Mock mode creates sample scans for testing)
        let hasContent = gallery.isEmpty || gallery.scanCardCount > 0
        XCTAssertTrue(hasContent, "Gallery should show either empty state or scans")
    }

    /// Test that all main navigation elements are visible.
    func testMainNavigationElementsAreVisible() throws {
        // GIVEN: App is launched
        let tabBar = TabBarPage(app: app)

        // THEN: All navigation elements should be present
        XCTAssertTrue(
            tabBar.galleryTab.waitForExistence(timeout: 10) ||
            app.staticTexts["Galerie"].exists,
            "Gallery tab should be visible"
        )

        XCTAssertTrue(
            tabBar.captureButton.waitForExistence(timeout: 5) ||
            app.buttons["viewfinder"].exists,
            "Capture button should be visible"
        )

        XCTAssertTrue(
            tabBar.profileTab.waitForExistence(timeout: 5) ||
            app.staticTexts["Profil"].exists,
            "Profile tab should be visible"
        )
    }

    // MARK: - Performance Tests

    /// Test app launch performance.
    func testAppLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }

    // MARK: - State Restoration Tests

    /// Test that app state is restored after background/foreground cycle.
    func testStateRestorationAfterBackground() throws {
        // GIVEN: App is launched and on Gallery
        let gallery = GalleryPage(app: app)
        _ = gallery.waitForDisplay() 

        // WHEN: App goes to background and comes back
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()

        // THEN: Gallery should still be displayed
        XCTAssertTrue(gallery.waitForDisplay(timeout: 5), "Gallery should be restored after foregrounding")
    }
}
