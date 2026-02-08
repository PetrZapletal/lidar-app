import XCTest

/// Page Object for the main tab bar navigation.
final class TabBarPage: BasePage {

    // MARK: - Elements

    /// Gallery tab button
    var galleryTab: XCUIElement {
        // Try accessibility identifier first, then fallback to label
        let identified = app.buttons[AccessibilityIdentifiers.TabBar.galleryTab]
        if identified.exists { return identified }

        // Fallback: find by label
        return app.buttons["Galerie"].firstMatch
    }

    /// Central capture button
    var captureButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.TabBar.captureButton]
        if identified.exists { return identified }

        // Fallback: find by icon
        return app.buttons["viewfinder"].firstMatch
    }

    /// Profile tab button
    var profileTab: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.TabBar.profileTab]
        if identified.exists { return identified }

        // Fallback: find by label
        return app.buttons["Profil"].firstMatch
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return galleryTab.exists || captureButton.exists || profileTab.exists
    }

    // MARK: - Actions

    /// Navigate to Gallery tab
    @discardableResult
    func tapGallery() -> GalleryPage {
        waitAndTap(galleryTab)
        return GalleryPage(app: app)
    }

    /// Tap capture button to open scan mode selector
    @discardableResult
    func tapCapture() -> ScanModeSelectorPage {
        waitAndTap(captureButton)
        return ScanModeSelectorPage(app: app)
    }

    /// Navigate to Profile tab
    @discardableResult
    func tapProfile() -> ProfilePage {
        waitAndTap(profileTab)
        return ProfilePage(app: app)
    }

    // MARK: - State Verification

    /// Check if Gallery tab is selected
    var isGallerySelected: Bool {
        galleryTab.isSelected
    }

    /// Check if Profile tab is selected
    var isProfileSelected: Bool {
        profileTab.isSelected
    }
}
