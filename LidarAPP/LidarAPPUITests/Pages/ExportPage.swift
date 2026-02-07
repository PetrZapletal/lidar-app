import XCTest

/// Page Object for the Export view.
final class ExportPage: BasePage {

    // MARK: - Elements

    /// Navigation title
    var navigationTitle: XCUIElement {
        app.navigationBars["Exportovat"].firstMatch
    }

    /// Done button
    var doneButton: XCUIElement {
        app.buttons["Hotovo"].firstMatch
    }

    // MARK: - 3D Format Options

    /// USDZ format row
    var usdzFormat: XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'USDZ'")).firstMatch
    }

    /// glTF format row
    var gltfFormat: XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'glTF'")).firstMatch
    }

    /// OBJ format row
    var objFormat: XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'OBJ'")).firstMatch
    }

    /// STL format row
    var stlFormat: XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'STL'")).firstMatch
    }

    /// PLY format row
    var plyFormat: XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'PLY'")).firstMatch
    }

    // MARK: - Document Options

    /// PDF format row
    var pdfFormat: XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'PDF'")).firstMatch
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return navigationTitle.waitForExistence(timeout: 5) ||
               usdzFormat.exists ||
               gltfFormat.exists
    }

    /// Verify all export formats are available
    func verifyAllFormatsPresent() -> Bool {
        let scrollView = app.scrollViews.firstMatch

        // Check 3D formats
        let has3DFormats = usdzFormat.exists || gltfFormat.exists || objFormat.exists

        // Scroll to see more if needed
        if scrollView.exists {
            _ = stlFormat.scrollToElement(in: scrollView, direction: .up, maxSwipes: 3)
        }

        return has3DFormats
    }

    // MARK: - Actions

    /// Dismiss export view
    @discardableResult
    func dismiss() -> ModelDetailPage {
        waitAndTap(doneButton)
        return ModelDetailPage(app: app)
    }

    /// Select USDZ format for export
    @discardableResult
    func selectUSDZ() -> Self {
        waitAndTap(usdzFormat)
        return self
    }

    /// Select glTF format for export
    @discardableResult
    func selectGLTF() -> Self {
        waitAndTap(gltfFormat)
        return self
    }

    /// Select OBJ format for export
    @discardableResult
    func selectOBJ() -> Self {
        waitAndTap(objFormat)
        return self
    }

    /// Select STL format for export
    @discardableResult
    func selectSTL() -> Self {
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            _ = stlFormat.scrollToElement(in: scrollView, direction: .up)
        }
        waitAndTap(stlFormat)
        return self
    }

    /// Select PLY format for export
    @discardableResult
    func selectPLY() -> Self {
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            _ = plyFormat.scrollToElement(in: scrollView, direction: .up)
        }
        waitAndTap(plyFormat)
        return self
    }

    /// Select PDF format for export
    @discardableResult
    func selectPDF() -> Self {
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            _ = pdfFormat.scrollToElement(in: scrollView, direction: .up)
        }
        waitAndTap(pdfFormat)
        return self
    }
}

/// Page Object for the Measurement view.
final class MeasurementPage: BasePage {

    // MARK: - Elements

    /// Close button
    var closeButton: XCUIElement {
        app.buttons["Zavrit"].firstMatch
    }

    /// Unit picker/selector
    var unitPicker: XCUIElement {
        app.pickers.firstMatch
    }

    /// Distance measurement label
    var distanceLabel: XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Measurement.distanceLabel].firstMatch
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return closeButton.waitForExistence(timeout: 5)
    }

    // MARK: - Actions

    /// Close measurement view
    @discardableResult
    func close() -> ModelDetailPage {
        waitAndTap(closeButton)
        return ModelDetailPage(app: app)
    }

    /// Change measurement unit
    @discardableResult
    func selectUnit(_ unit: String) -> Self {
        if waitFor(unitPicker) {
            unitPicker.pickerWheels.firstMatch.adjust(toPickerWheelValue: unit)
        }
        return self
    }
}
