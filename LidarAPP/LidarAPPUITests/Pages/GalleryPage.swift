import XCTest

/// Page Object for the Gallery view displaying saved scans.
final class GalleryPage: BasePage {

    // MARK: - Elements

    /// The main gallery view container
    var galleryView: XCUIElement {
        app.otherElements[AccessibilityIdentifiers.Gallery.view].firstMatch
    }

    /// Search field for filtering scans
    var searchField: XCUIElement {
        let identified = app.searchFields[AccessibilityIdentifiers.Gallery.searchField]
        if identified.exists { return identified }

        // Fallback: find by placeholder
        return app.searchFields["Hledat modely"].firstMatch
    }

    /// Sort/filter button
    var sortButton: XCUIElement {
        let identified = app.buttons[AccessibilityIdentifiers.Gallery.sortButton]
        if identified.exists { return identified }

        // Fallback: find by icon
        return app.buttons["arrow.up.arrow.down.circle"].firstMatch
    }

    /// Empty state view when no scans exist
    var emptyStateView: XCUIElement {
        let identified = app.otherElements[AccessibilityIdentifiers.Gallery.emptyStateView]
        if identified.exists { return identified }

        // Fallback: find by text content with diacritics
        let withDiacritics = app.staticTexts["Žádné modely"]
        if withDiacritics.exists { return withDiacritics.firstMatch }

        return app.staticTexts["Zadne modely"].firstMatch
    }

    /// Empty state description text
    var emptyStateDescription: XCUIElement {
        let withDiacritics = app.staticTexts["Vytvořte svůj první 3D sken pomocí tlačítka skenování"]
        if withDiacritics.exists { return withDiacritics.firstMatch }

        return app.staticTexts["Vytvorte svuj prvni 3D sken pomoci tlacitka skenovani"].firstMatch
    }

    /// Scroll view containing scan cards
    var scanGrid: XCUIElement {
        app.scrollViews.firstMatch
    }

    /// Navigation title
    var navigationTitle: XCUIElement {
        app.navigationBars["Moje 3D modely"].firstMatch
    }

    // MARK: - Computed Properties

    /// Get all scan cards currently visible
    var scanCards: [XCUIElement] {
        // SwiftUI grid items may render as buttons or other elements
        // First try cells (TableView/CollectionView style)
        let cells = app.cells.allElementsBoundByIndex
        if !cells.isEmpty { return cells }

        // SwiftUI LazyVGrid doesn't use cells - look for specific scan card elements
        // Check for images inside the scroll view (but not tab bar icons)
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            let imagesInScroll = scrollView.images.allElementsBoundByIndex
            if !imagesInScroll.isEmpty { return imagesInScroll }
        }

        // Return empty - don't fall back to app.images as those might be UI chrome
        return []
    }

    /// Number of visible scan cards
    var scanCardCount: Int {
        // First check: if showing empty state, no cards
        if isEmpty { return 0 }

        // Return the actual count of scan cards we can find
        // This must be consistent with scanCards property
        return scanCards.count
    }

    /// Check if gallery is empty
    var isEmpty: Bool {
        // Check for empty state accessibility identifier
        if app.otherElements[AccessibilityIdentifiers.Gallery.emptyStateView].exists {
            return true
        }

        // Check for ContentUnavailableView text with diacritics
        if app.staticTexts["Žádné modely"].exists {
            return true
        }

        // Check without diacritics
        if app.staticTexts["Zadne modely"].exists {
            return true
        }

        // Check for ContentUnavailableView description text
        if app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'první 3D sken'")).count > 0 {
            return true
        }

        // Check for ContentUnavailableView description without diacritics
        if app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'prvni 3D sken'")).count > 0 {
            return true
        }

        // Check by partial match on "modely" text
        if app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'modely' AND label CONTAINS 'dn'")).count > 0 {
            return true
        }

        return false
    }

    // MARK: - Verification

    override func isDisplayed() -> Bool {
        return navigationTitle.exists ||
               app.navigationBars.staticTexts["Moje 3D modely"].exists ||
               emptyStateView.exists ||
               scanGrid.exists
    }

    /// Verify empty state is displayed correctly
    func verifyEmptyState() -> Bool {
        guard isEmpty else { return false }
        return emptyStateView.exists ||
               app.staticTexts["Žádné modely"].exists ||
               app.staticTexts["Zadne modely"].exists
    }

    // MARK: - Actions

    /// Search for scans with given text
    @discardableResult
    func search(for text: String) -> Self {
        if waitFor(searchField) {
            searchField.tap()
            searchField.typeText(text)
        }
        return self
    }

    /// Clear search field
    @discardableResult
    func clearSearch() -> Self {
        if searchField.exists {
            // Tap the clear button in search field
            let clearButton = searchField.buttons["Clear text"].firstMatch
            if clearButton.exists {
                clearButton.tap()
            }
        }
        return self
    }

    /// Open sort menu
    @discardableResult
    func openSortMenu() -> Self {
        waitAndTap(sortButton)
        return self
    }

    /// Select sort option
    @discardableResult
    func selectSortOption(_ option: SortOption) -> Self {
        openSortMenu()
        let optionButton = app.buttons[option.rawValue]
        waitAndTap(optionButton)
        return self
    }

    /// Tap on scan card at index
    @discardableResult
    func tapScanCard(at index: Int) -> ModelDetailPage {
        guard index < scanCards.count else {
            XCTFail("Scan card index \(index) out of bounds")
            return ModelDetailPage(app: app)
        }
        scanCards[index].tap()
        return ModelDetailPage(app: app)
    }

    /// Tap on scan card with specific name
    @discardableResult
    func tapScanCard(named name: String) -> ModelDetailPage {
        let card = app.staticTexts[name].firstMatch
        if waitFor(card) {
            card.tap()
        }
        return ModelDetailPage(app: app)
    }

    /// Pull to refresh (if supported)
    @discardableResult
    func pullToRefresh() -> Self {
        scanGrid.swipeDown()
        return self
    }

    // MARK: - Sort Options

    enum SortOption: String {
        case newest = "Nejnovejsi"
        case oldest = "Nejstarsi"
        case nameAZ = "Nazev A-Z"
        case largest = "Nejvetsi"
    }
}
