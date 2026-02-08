import XCTest

/// Page Object for the Scanning view (LiDAR, RoomPlan, or ObjectCapture).
///
/// Note: Most AR/LiDAR functionality cannot be tested in simulator.
/// This page focuses on UI element testing and mock mode behavior.
final class ScanningPage: BasePage {

    // MARK: - Elements

    /// Status bar showing tracking state and stats
    var statusBar: XCUIElement {
        app.otherElements[AccessibilityIdentifiers.Scanning.statusBar].firstMatch
    }

    /// Main capture/pause button
    var captureButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Scanning.captureButton]
        if identified.exists { return identified }

        // Fallback: look for the capture button by accessibility label
        let withDiacritics = app.buttons.containing(NSPredicate(format: "label CONTAINS 'skenování'"))
        if withDiacritics.count > 0 { return withDiacritics.firstMatch }

        return app.buttons.containing(NSPredicate(format: "label CONTAINS 'skenovani'")).firstMatch
    }

    /// Stop button
    var stopButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Scanning.stopButton]
        if identified.exists { return identified }

        return app.buttons["Stop"].firstMatch
    }

    /// Close button
    var closeButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Scanning.closeButton]
        if identified.exists { return identified }

        let withDiacritics = app.buttons["Zavřít"]
        if withDiacritics.exists { return withDiacritics.firstMatch }

        return app.buttons["Zavrit"].firstMatch
    }

    /// Mesh toggle button
    var meshToggle: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Scanning.meshToggle]
        if identified.exists { return identified }

        return app.buttons["Mesh"].firstMatch
    }

    /// Settings button
    var settingsButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Scanning.settingsButton]
        if identified.exists { return identified }

        return app.buttons["gearshape.fill"].firstMatch
    }

    /// Mock mode warning banner
    var mockModeWarning: XCUIElement {
        let identified = app.staticTexts[AccessibilityIdentifiers.Scanning.mockModeWarning]
        if identified.exists { return identified }

        return app.staticTexts["MOCK MODE AKTIVNI"].firstMatch
    }

    // MARK: - Statistics Labels

    /// Point count label
    var pointCountLabel: XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Scanning.pointCountLabel].firstMatch
    }

    /// Mesh face count label
    var meshFaceCountLabel: XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Scanning.meshFaceCountLabel].firstMatch
    }

    /// Duration label
    var durationLabel: XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Scanning.durationLabel].firstMatch
    }

    // MARK: - Computed Properties

    /// Check if mock mode is active
    var isMockModeActive: Bool {
        mockModeWarning.exists
    }

    /// Check if scanning is in progress
    var isScanning: Bool {
        // Look for pause button (visible during scanning)
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Pozastavit'")).firstMatch.exists
    }

    /// Check if stop button is visible (indicates active scanning)
    var canStop: Bool {
        stopButton.exists && stopButton.isEnabled
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        // The scanning view should have the capture button or close button
        return captureButton.waitForExistence(timeout: 5) ||
               closeButton.exists ||
               mockModeWarning.exists
    }

    /// Verify mock mode banner is displayed (for simulator tests)
    func verifyMockModeActive() -> Bool {
        return mockModeWarning.waitForExistence(timeout: 5)
    }

    // MARK: - Actions

    /// Start or pause scanning
    @discardableResult
    func tapCapture() -> Self {
        waitAndTap(captureButton)
        return self
    }

    /// Stop scanning and show results
    @discardableResult
    func tapStop() -> ScanResultsPage {
        waitAndTap(stopButton)
        return ScanResultsPage(app: app)
    }

    /// Close scanning view without saving
    @discardableResult
    func close() -> TabBarPage {
        waitAndTap(closeButton)
        return TabBarPage(app: app)
    }

    /// Toggle mesh visualization
    @discardableResult
    func toggleMesh() -> Self {
        waitAndTap(meshToggle)
        return self
    }

    /// Open settings
    @discardableResult
    func openSettings() -> SettingsPage {
        waitAndTap(settingsButton)
        return SettingsPage(app: app)
    }

    /// Wait for scanning to start (in mock mode)
    @discardableResult
    func waitForScanningToStart(timeout: TimeInterval = 10) -> Self {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if isScanning || pointCountLabel.exists {
                return self
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return self
    }

    /// Perform a mock scan session (capture -> wait -> stop)
    @discardableResult
    func performMockScan(duration: TimeInterval = 3) -> ScanResultsPage {
        tapCapture()
        Thread.sleep(forTimeInterval: duration)
        return tapStop()
    }
}

/// Page Object for scan results view (shown after stopping a scan).
final class ScanResultsPage: BasePage {

    // MARK: - Elements

    /// Save button
    var saveButton: XCUIElement {
        app.buttons["Ulozit"].firstMatch
    }

    /// Discard button
    var discardButton: XCUIElement {
        app.buttons["Zahodit"].firstMatch
    }

    /// Scan name text field
    var nameTextField: XCUIElement {
        app.textFields.firstMatch
    }

    /// Preview of the scan
    var previewView: XCUIElement {
        app.otherElements["scanPreview"].firstMatch
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return saveButton.waitForExistence(timeout: 10) ||
               discardButton.exists ||
               nameTextField.exists
    }

    // MARK: - Actions

    /// Enter name for the scan
    @discardableResult
    func enterName(_ name: String) -> Self {
        if waitFor(nameTextField) {
            nameTextField.clearAndTypeText(name)
        }
        return self
    }

    /// Save the scan
    @discardableResult
    func save() -> GalleryPage {
        waitAndTap(saveButton)
        return GalleryPage(app: app)
    }

    /// Discard the scan
    @discardableResult
    func discard() -> TabBarPage {
        waitAndTap(discardButton)
        return TabBarPage(app: app)
    }
}
