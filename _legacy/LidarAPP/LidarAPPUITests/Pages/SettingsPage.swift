import XCTest

/// Page Object for the Settings view.
final class SettingsPage: BasePage {

    // MARK: - Elements

    /// Navigation title
    var navigationTitle: XCUIElement {
        let withDiacritics = app.navigationBars["Nastavení"]
        if withDiacritics.exists { return withDiacritics.firstMatch }

        return app.navigationBars["Nastaveni"].firstMatch
    }

    /// Done button
    var doneButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Settings.doneButton]
        if identified.exists { return identified }

        return app.buttons["Hotovo"].firstMatch
    }

    // MARK: - Developer Section

    /// Mock mode toggle
    var mockModeToggle: XCUIElement {
        let identified = app.switches[AccessibilityIdentifiers.Settings.mockModeToggle]
        if identified.exists { return identified }

        // Fallback: find by label
        return app.switches["Mock Mode"].firstMatch
    }

    /// Mock data preview link
    var mockDataPreviewLink: XCUIElement {
        app.buttons["Preview mock dat"].firstMatch
    }

    /// Simulator indicator
    var simulatorIndicator: XCUIElement {
        app.staticTexts["Simulator"].firstMatch
    }

    // MARK: - Debug Upload Section

    /// Raw data mode toggle
    var rawDataModeToggle: XCUIElement {
        let identified = app.switches[AccessibilityIdentifiers.Settings.rawDataModeToggle]
        if identified.exists { return identified }

        return app.switches["Raw Data Mode"].firstMatch
    }

    /// Tailscale IP text field
    var tailscaleIPField: XCUIElement {
        app.textFields["100.x.x.x"].firstMatch
    }

    /// Test connection button
    var testConnectionButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Settings.testConnectionButton]
        if identified.exists { return identified }

        return app.buttons["Test Connection"].firstMatch
    }

    /// Reset to defaults button
    var resetDefaultsButton: XCUIElement {
        app.buttons["Obnovit vychozi nastaveni"].firstMatch
    }

    // MARK: - Processing Section

    /// Depth fusion toggle
    var depthFusionToggle: XCUIElement {
        // Try accessibility identifier first
        let identified = app.switches[AccessibilityIdentifiers.Settings.depthFusionToggle]
        if identified.exists { return identified }

        // Fallback: find by label
        return app.switches["Depth Fusion"].firstMatch
    }

    /// Target point count stepper
    var pointCountStepper: XCUIElement {
        app.steppers.firstMatch
    }

    // MARK: - Quality Section

    /// Mesh resolution picker
    var meshResolutionPicker: XCUIElement {
        app.buttons["Rozliseni mesh"].firstMatch
    }

    /// Texture resolution picker
    var textureResolutionPicker: XCUIElement {
        app.buttons["Rozliseni textur"].firstMatch
    }

    // MARK: - Export Section

    /// Output formats link
    var outputFormatsLink: XCUIElement {
        let withDiacritics = app.buttons["Výstupní formáty"]
        if withDiacritics.exists { return withDiacritics.firstMatch }

        return app.buttons["Vystupni formaty"].firstMatch
    }

    // MARK: - Diagnostics Section

    /// Export diagnostics button
    var exportDiagnosticsButton: XCUIElement {
        app.buttons["Exportovat diagnostiku"].firstMatch
    }

    /// Crash details link
    var crashDetailsLink: XCUIElement {
        app.buttons["Crash detaily"].firstMatch
    }

    /// Component testing link
    var componentTestingLink: XCUIElement {
        app.buttons["Testovani komponent"].firstMatch
    }

    // MARK: - About Section

    /// Version label
    var versionLabel: XCUIElement {
        app.staticTexts["Verze"].firstMatch
    }

    /// Build label
    var buildLabel: XCUIElement {
        app.staticTexts["Build"].firstMatch
    }

    /// Privacy policy link
    var privacyPolicyLink: XCUIElement {
        let withDiacritics = app.buttons["Zásady ochrany osobních údajů"]
        if withDiacritics.exists { return withDiacritics.firstMatch }

        // Try as links (Link is a button in SwiftUI)
        let link = app.links["Zásady ochrany osobních údajů"]
        if link.exists { return link.firstMatch }

        return app.buttons["Zasady ochrany osobnich udaju"].firstMatch
    }

    /// Terms of use link
    var termsOfUseLink: XCUIElement {
        app.buttons["Podminky pouziti"].firstMatch
    }

    // MARK: - Computed Properties

    /// Check if mock mode is enabled
    var isMockModeEnabled: Bool {
        guard mockModeToggle.exists else { return false }
        return (mockModeToggle.value as? String) == "1"
    }

    /// Check if raw data mode is enabled
    var isRawDataModeEnabled: Bool {
        guard rawDataModeToggle.exists else { return false }
        return (rawDataModeToggle.value as? String) == "1"
    }

    /// Check if depth fusion is enabled
    var isDepthFusionEnabled: Bool {
        guard depthFusionToggle.exists else { return false }
        return (depthFusionToggle.value as? String) == "1"
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return navigationTitle.waitForExistence(timeout: 5) ||
               doneButton.exists ||
               mockModeToggle.exists
    }

    // MARK: - Actions

    /// Dismiss settings
    @discardableResult
    func dismiss() -> ProfilePage {
        waitAndTap(doneButton)
        return ProfilePage(app: app)
    }

    /// Toggle mock mode
    @discardableResult
    func toggleMockMode() -> Self {
        if waitFor(mockModeToggle) {
            mockModeToggle.tap()
        }
        return self
    }

    /// Toggle raw data mode
    @discardableResult
    func toggleRawDataMode() -> Self {
        if waitFor(rawDataModeToggle) {
            rawDataModeToggle.tap()
        }
        return self
    }

    /// Toggle depth fusion
    @discardableResult
    func toggleDepthFusion() -> Self {
        if waitFor(depthFusionToggle) {
            depthFusionToggle.tap()
        }
        return self
    }

    /// Test backend connection
    @discardableResult
    func testConnection() -> Self {
        waitAndTap(testConnectionButton)
        // Wait for connection test to complete
        Thread.sleep(forTimeInterval: 2)
        return self
    }

    /// Reset settings to defaults
    @discardableResult
    func resetToDefaults() -> Self {
        // Scroll to find the button if needed
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            _ = resetDefaultsButton.scrollToElement(in: scrollView, direction: .up)
        }
        waitAndTap(resetDefaultsButton)
        return self
    }

    /// Open mock data preview
    @discardableResult
    func openMockDataPreview() -> Self {
        waitAndTap(mockDataPreviewLink)
        return self
    }

    /// Open output formats selection
    @discardableResult
    func openOutputFormats() -> Self {
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            _ = outputFormatsLink.scrollToElement(in: scrollView, direction: .up)
        }
        waitAndTap(outputFormatsLink)
        return self
    }

    /// Export diagnostics
    @discardableResult
    func exportDiagnostics() -> Self {
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            _ = exportDiagnosticsButton.scrollToElement(in: scrollView, direction: .up)
        }
        waitAndTap(exportDiagnosticsButton)
        return self
    }

    /// Navigate back from sub-settings
    @discardableResult
    func goBack() -> Self {
        super.navigateBack()
        return self
    }
}
