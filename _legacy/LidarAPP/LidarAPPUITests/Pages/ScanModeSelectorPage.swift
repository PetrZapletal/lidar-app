import XCTest

/// Page Object for the Scan Mode Selector sheet.
final class ScanModeSelectorPage: BasePage {

    // MARK: - Elements

    /// Sheet title
    var title: XCUIElement {
        let withDiacritics = app.staticTexts["Vyberte režim skenování"]
        if withDiacritics.exists { return withDiacritics.firstMatch }

        return app.staticTexts["Vyberte rezim skenovani"].firstMatch
    }

    /// Cancel button
    var cancelButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.ScanModeSelector.cancelButton]
        if identified.exists { return identified }

        let withDiacritics = app.buttons["Zrušit"]
        if withDiacritics.exists { return withDiacritics.firstMatch }

        return app.buttons["Zrusit"].firstMatch
    }

    /// Exterior scanning card (LiDAR)
    var exteriorCard: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.ScanModeSelector.exteriorCard]
        if identified.exists { return identified }

        // Fallback: find by text content
        return app.buttons.containing(NSPredicate(format: "label CONTAINS 'Exterier'")).firstMatch
    }

    /// Interior scanning card (RoomPlan)
    var interiorCard: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.ScanModeSelector.interiorCard]
        if identified.exists { return identified }

        return app.buttons.containing(NSPredicate(format: "label CONTAINS 'Interier'")).firstMatch
    }

    /// Object scanning card (ObjectCapture)
    var objectCard: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.ScanModeSelector.objectCard]
        if identified.exists { return identified }

        return app.buttons.containing(NSPredicate(format: "label CONTAINS 'Objekt'")).firstMatch
    }

    // MARK: - Computed Properties

    /// Check if exterior mode is supported (enabled)
    var isExteriorSupported: Bool {
        exteriorCard.isEnabled
    }

    /// Check if interior mode is supported
    var isInteriorSupported: Bool {
        interiorCard.isEnabled
    }

    /// Check if object mode is supported
    var isObjectSupported: Bool {
        objectCard.isEnabled
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return title.waitForExistence(timeout: 5) ||
               exteriorCard.exists ||
               interiorCard.exists ||
               objectCard.exists
    }

    /// Verify all mode cards are present
    func verifyAllModesPresent() -> Bool {
        return exteriorCard.exists && interiorCard.exists && objectCard.exists
    }

    // MARK: - Actions

    /// Select exterior scanning mode
    @discardableResult
    func selectExterior() -> ScanningPage {
        waitAndTap(exteriorCard)
        return ScanningPage(app: app)
    }

    /// Select interior scanning mode (RoomPlan)
    @discardableResult
    func selectInterior() -> ScanningPage {
        waitAndTap(interiorCard)
        return ScanningPage(app: app)
    }

    /// Select object scanning mode
    @discardableResult
    func selectObject() -> ScanningPage {
        waitAndTap(objectCard)
        return ScanningPage(app: app)
    }

    /// Cancel and close the selector
    @discardableResult
    func cancel() -> TabBarPage {
        waitAndTap(cancelButton)
        return TabBarPage(app: app)
    }

    /// Swipe down to dismiss
    @discardableResult
    func swipeDownToDismiss() -> TabBarPage {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.1, thenDragTo: end)
        return TabBarPage(app: app)
    }
}
