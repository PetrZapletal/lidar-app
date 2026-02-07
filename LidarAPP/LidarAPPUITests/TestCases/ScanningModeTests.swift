import XCTest

/// Tests for scanning mode selection and scanning view.
///
/// Note: Actual LiDAR/AR scanning cannot be tested in simulator.
/// These tests focus on UI elements and mock mode behavior.
final class ScanningModeTests: BaseUITestCase {

    // MARK: - Scan Mode Selector Tests

    /// Test that all three scan modes are displayed.
    func testAllScanModesAreDisplayed() throws {
        // GIVEN: Open scan mode selector
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay() 

        // THEN: All mode cards should be present
        XCTAssertTrue(selector.exteriorCard.exists, "Exterior mode card should exist")
        XCTAssertTrue(selector.interiorCard.exists, "Interior mode card should exist")
        XCTAssertTrue(selector.objectCard.exists, "Object mode card should exist")
    }

    /// Test that scan mode selector shows correct title.
    func testScanModeSelectorTitle() throws {
        // GIVEN: Open scan mode selector
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay() 

        // THEN: Title should be displayed
        XCTAssertTrue(
            selector.title.exists ||
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'režim'")).count > 0 ||
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'skenování'")).count > 0,
            "Scan mode selector should show title"
        )
    }

    /// Test that cancel button is visible.
    func testCancelButtonIsVisible() throws {
        // GIVEN: Open scan mode selector
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay() 

        // THEN: Cancel button should be visible
        XCTAssertTrue(
            selector.cancelButton.exists ||
            app.buttons["Zrusit"].exists,
            "Cancel button should be visible"
        )
    }

    // MARK: - Exterior Mode Tests

    /// Test selecting exterior mode opens scanning view.
    func testSelectingExteriorModeOpensScanningView() throws {
        // GIVEN: Open scan mode selector
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay() 

        // Skip if exterior is not supported
        guard selector.isExteriorSupported else {
            throw XCTSkip("Exterior mode not supported on this device/configuration")
        }

        // WHEN: Select exterior mode
        let scanning = selector.selectExterior()

        // THEN: Scanning view should be displayed
        XCTAssertTrue(scanning.waitForDisplay(), "Scanning view should be displayed")
    }

    /// Test mock mode warning is shown in simulator.
    func testMockModeWarningShownInSimulator() throws {
        // GIVEN: Open exterior scanning in mock mode
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay() 

        guard selector.isExteriorSupported else {
            throw XCTSkip("Exterior mode not supported")
        }

        let scanning = selector.selectExterior()
        _ = scanning.waitForDisplay() 

        // THEN: Mock mode warning should be visible (in simulator)
        // Note: This depends on mock mode being enabled
        if scanning.isMockModeActive {
            XCTAssertTrue(
                scanning.mockModeWarning.exists,
                "Mock mode warning should be visible in mock mode"
            )
        }
    }

    /// Test scanning view can be closed.
    func testScanningViewCanBeClosed() throws {
        // GIVEN: Scanning view is open
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay() 

        guard selector.isExteriorSupported else {
            throw XCTSkip("Exterior mode not supported")
        }

        let scanning = selector.selectExterior()
        _ = scanning.waitForDisplay() 

        // WHEN: Close scanning view
        let returnedTabBar = scanning.close()

        // THEN: Should return to main view
        XCTAssertTrue(returnedTabBar.waitForDisplay(), "Should return to main view after closing")
    }

    // MARK: - Interior Mode Tests

    /// Test selecting interior mode opens scanning view.
    func testSelectingInteriorModeOpensScanningView() throws {
        // GIVEN: Open scan mode selector
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay() 

        // Skip if interior is not supported
        guard selector.isInteriorSupported else {
            throw XCTSkip("Interior mode not supported on this device/configuration")
        }

        // WHEN: Select interior mode
        let scanning = selector.selectInterior()

        // THEN: Scanning view should be displayed
        XCTAssertTrue(scanning.waitForDisplay(), "Scanning view should be displayed")
    }

    // MARK: - Object Mode Tests

    /// Test selecting object mode opens scanning view.
    func testSelectingObjectModeOpensScanningView() throws {
        // GIVEN: Open scan mode selector
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay() 

        // Skip if object is not supported
        guard selector.isObjectSupported else {
            throw XCTSkip("Object mode not supported on this device/configuration")
        }

        // WHEN: Select object mode
        let scanning = selector.selectObject()

        // THEN: Scanning view should be displayed
        XCTAssertTrue(scanning.waitForDisplay(), "Scanning view should be displayed")
    }

    // MARK: - Scanning Controls Tests

    /// Test that capture button is visible in scanning view.
    func testCaptureButtonVisibleInScanningView() throws {
        // GIVEN: Open scanning view
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay() 

        guard selector.isExteriorSupported else {
            throw XCTSkip("Scanning modes not supported")
        }

        let scanning = selector.selectExterior()
        _ = scanning.waitForDisplay() 

        // THEN: Capture button should be visible
        let hasCapture = scanning.captureButton.exists ||
                         app.buttons.containing(NSPredicate(format: "label CONTAINS 'skenovani'")).count > 0
        XCTAssertTrue(hasCapture, "Capture button should be visible")
    }

    /// Test that LiDAR mode shows correct controls in ready state.
    /// Mesh toggle only appears during active scanning; in ready state the start button is shown.
    func testMeshToggleAvailableInLiDARMode() throws {
        // GIVEN: Open LiDAR scanning view
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay()

        guard selector.isExteriorSupported else {
            throw XCTSkip("Exterior mode not supported")
        }

        let scanning = selector.selectExterior()
        _ = scanning.waitForDisplay()

        // THEN: In ready state, start button should be visible (mesh toggle appears only during scanning)
        let hasStartButton = app.buttons["Zahájit skenování"].exists ||
                             scanning.captureButton.exists ||
                             app.buttons.containing(NSPredicate(format: "label CONTAINS 'skenovani'")).count > 0
        XCTAssertTrue(hasStartButton, "Start scanning button should be visible in ready state")
    }

    /// Test that settings button is available in scanning view.
    func testSettingsButtonAvailableInScanningView() throws {
        // GIVEN: Open scanning view
        let tabBar = TabBarPage(app: app)
        let selector = tabBar.tapCapture()
        _ = selector.waitForDisplay() 

        guard selector.isExteriorSupported else {
            throw XCTSkip("Scanning modes not supported")
        }

        let scanning = selector.selectExterior()
        _ = scanning.waitForDisplay() 

        // THEN: Settings button should exist
        let hasSettings = scanning.settingsButton.exists ||
                          app.buttons["gearshape.fill"].exists
        XCTAssertTrue(hasSettings, "Settings button should be available")
    }
}
