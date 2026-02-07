import XCTest

/// Page Object for the Model Detail view.
final class ModelDetailPage: BasePage {

    // MARK: - Elements

    /// Model title in navigation bar
    var titleLabel: XCUIElement {
        app.navigationBars.staticTexts.firstMatch
    }

    /// Menu button (three dots)
    var menuButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.ModelDetail.menuButton]
        if identified.exists { return identified }

        return app.buttons["ellipsis.circle"].firstMatch
    }

    // MARK: - Menu Items

    /// Share menu item
    var shareButton: XCUIElement {
        app.buttons["Sdilet"].firstMatch
    }

    /// Export menu item
    var exportMenuButton: XCUIElement {
        app.buttons["Exportovat"].firstMatch
    }

    /// Rename menu item
    var renameButton: XCUIElement {
        app.buttons["Prejmenovat"].firstMatch
    }

    /// Delete menu item
    var deleteButton: XCUIElement {
        app.buttons["Smazat"].firstMatch
    }

    // MARK: - Action Bar Buttons

    /// AI processing button
    var aiButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.ModelDetail.aiButton]
        if identified.exists { return identified }

        return app.buttons["AI"].firstMatch
    }

    /// Measure button
    var measureButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.ModelDetail.measureButton]
        if identified.exists { return identified }

        return app.buttons["Merit"].firstMatch
    }

    /// 3D+ viewer button
    var viewer3DButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.ModelDetail.viewer3DButton]
        if identified.exists { return identified }

        return app.buttons["3D+"].firstMatch
    }

    /// AR button
    var arButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.ModelDetail.arButton]
        if identified.exists { return identified }

        return app.buttons["AR"].firstMatch
    }

    /// Export button in action bar
    var exportButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.ModelDetail.exportActionButton]
        if identified.exists { return identified }

        return app.buttons["Export"].firstMatch
    }

    // MARK: - AI Processing

    /// AI processing progress indicator
    var aiProgressIndicator: XCUIElement {
        app.otherElements[AccessibilityIdentifiers.ModelDetail.aiProgressIndicator].firstMatch
    }

    /// AI processing status text
    var aiStatusText: XCUIElement {
        // Look for any of the processing stage texts
        let stages = ["Analyzing", "Processing", "Completing"]
        for stage in stages {
            let text = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", stage)).firstMatch
            if text.exists { return text }
        }
        return app.staticTexts["AIStatus"].firstMatch
    }

    // MARK: - Alerts

    /// Rename alert
    var renameAlert: XCUIElement {
        app.alerts["Prejmenovat model"].firstMatch
    }

    /// Rename text field in alert
    var renameTextField: XCUIElement {
        renameAlert.textFields.firstMatch
    }

    /// Delete confirmation alert
    var deleteAlert: XCUIElement {
        app.alerts["Smazat model?"].firstMatch
    }

    // MARK: - Computed Properties

    /// Check if AI processing is in progress
    var isAIProcessing: Bool {
        aiProgressIndicator.exists || aiStatusText.exists
    }

    /// Get current model name from title
    var modelName: String? {
        titleLabel.label
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return aiButton.waitForExistence(timeout: 5) ||
               measureButton.exists ||
               exportButton.exists
    }

    // MARK: - Navigation Actions

    /// Navigate back to gallery
    @discardableResult
    func navigateBack() -> GalleryPage {
        super.navigateBack()
        return GalleryPage(app: app)
    }

    // MARK: - Menu Actions

    /// Open the options menu
    @discardableResult
    func openMenu() -> Self {
        waitAndTap(menuButton)
        return self
    }

    /// Tap share in menu
    @discardableResult
    func tapShare() -> Self {
        openMenu()
        waitAndTap(shareButton)
        return self
    }

    /// Tap export in menu
    @discardableResult
    func tapExportFromMenu() -> ExportPage {
        openMenu()
        waitAndTap(exportMenuButton)
        return ExportPage(app: app)
    }

    /// Tap rename in menu
    @discardableResult
    func tapRename() -> Self {
        openMenu()
        waitAndTap(renameButton)
        return self
    }

    /// Tap delete in menu
    @discardableResult
    func tapDelete() -> Self {
        openMenu()
        waitAndTap(deleteButton)
        return self
    }

    // MARK: - Rename Flow

    /// Rename the model
    @discardableResult
    func rename(to newName: String) -> Self {
        tapRename()

        // Wait for alert and enter new name
        if waitFor(renameAlert) {
            if renameTextField.exists {
                renameTextField.clearAndTypeText(newName)
            }
            // Tap save
            let saveButton = renameAlert.buttons["Ulozit"]
            waitAndTap(saveButton)
        }

        return self
    }

    /// Cancel rename
    @discardableResult
    func cancelRename() -> Self {
        if renameAlert.exists {
            let cancelButton = renameAlert.buttons["Zrusit"]
            waitAndTap(cancelButton)
        }
        return self
    }

    // MARK: - Delete Flow

    /// Delete the model (with confirmation)
    @discardableResult
    func deleteWithConfirmation() -> GalleryPage {
        tapDelete()

        // Confirm deletion
        if waitFor(deleteAlert) {
            let confirmButton = deleteAlert.buttons["Smazat"]
            waitAndTap(confirmButton)
        }

        return GalleryPage(app: app)
    }

    /// Cancel delete
    @discardableResult
    func cancelDelete() -> Self {
        if deleteAlert.exists {
            let cancelButton = deleteAlert.buttons["Zrusit"]
            waitAndTap(cancelButton)
        }
        return self
    }

    // MARK: - Action Bar Actions

    /// Start AI processing
    @discardableResult
    func startAIProcessing() -> Self {
        waitAndTap(aiButton)
        return self
    }

    /// Wait for AI processing to complete
    @discardableResult
    func waitForAIProcessing(timeout: TimeInterval = 60) -> Self {
        // Wait for progress indicator to appear
        _ = waitFor(aiProgressIndicator, timeout: 5)

        // Then wait for it to disappear
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: aiProgressIndicator)
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)

        return self
    }

    /// Open measurement tool
    @discardableResult
    func openMeasurement() -> MeasurementPage {
        waitAndTap(measureButton)
        return MeasurementPage(app: app)
    }

    /// Open enhanced 3D viewer
    @discardableResult
    func open3DViewer() -> Self {
        waitAndTap(viewer3DButton)
        return self
    }

    /// Open AR view
    @discardableResult
    func openARView() -> Self {
        waitAndTap(arButton)
        return self
    }

    /// Open export view
    @discardableResult
    func openExport() -> ExportPage {
        waitAndTap(exportButton)
        return ExportPage(app: app)
    }
}
