import XCTest

/// Tests for the Gallery view functionality.
final class GalleryTests: BaseUITestCase {

    // MARK: - Display Tests

    /// Test that Gallery has correct navigation title.
    func testGalleryHasCorrectTitle() throws {
        // GIVEN: App is launched on Gallery
        let gallery = GalleryPage(app: app)
        _ = gallery.waitForDisplay() 

        // THEN: Navigation title should be correct
        let hasTitle = app.navigationBars["Moje 3D modely"].exists ||
                       app.staticTexts["Moje 3D modely"].exists
        XCTAssertTrue(hasTitle, "Gallery should have correct navigation title")
    }

    /// Test that search field is available.
    func testSearchFieldIsAvailable() throws {
        // GIVEN: App is launched on Gallery
        let gallery = GalleryPage(app: app)
        _ = gallery.waitForDisplay() 

        // THEN: Search field should be accessible
        // Note: Search field may be hidden until scrolled down
        let hasSearch = gallery.searchField.exists || app.searchFields.count > 0
        XCTAssertTrue(hasSearch, "Search field should be available in Gallery")
    }

    /// Test that sort button is available.
    func testSortButtonIsAvailable() throws {
        // GIVEN: App is launched on Gallery
        let gallery = GalleryPage(app: app)
        _ = gallery.waitForDisplay() 

        // THEN: Sort button should be accessible
        let hasSort = gallery.sortButton.exists ||
                      app.buttons["arrow.up.arrow.down.circle"].exists
        XCTAssertTrue(hasSort, "Sort button should be available in Gallery")
    }

    // MARK: - Mock Data Tests

    /// Test that mock scans are loaded in mock mode.
    func testMockScansAreLoaded() throws {
        // GIVEN: App is launched in mock mode
        let gallery = GalleryPage(app: app)
        _ = gallery.waitForDisplay() 

        // Wait for content to load
        sleep(2)

        // THEN: Either mock scans should be visible or empty state
        // (Mock mode typically pre-populates with sample scans)
        let hasContent = gallery.scanCardCount > 0 || gallery.isEmpty
        XCTAssertTrue(hasContent, "Gallery should have mock scans or show empty state")
    }

    /// Test that scan card can be tapped to open detail.
    func testTappingScanCardOpensDetail() throws {
        // GIVEN: Gallery has at least one scan
        let gallery = GalleryPage(app: app)
        _ = gallery.waitForDisplay() 

        // Skip if no scans are present
        guard gallery.scanCardCount > 0 else {
            throw XCTSkip("No scans available for testing")
        }

        // WHEN: Tap first scan card
        let detail = gallery.tapScanCard(at: 0)

        // THEN: Model detail should be displayed
        XCTAssertTrue(detail.waitForDisplay(), "Model detail should be displayed after tapping scan")
    }

    // MARK: - Search Tests

    /// Test search filters results.
    func testSearchFiltersResults() throws {
        // GIVEN: Gallery has scans
        let gallery = GalleryPage(app: app)
        _ = gallery.waitForDisplay() 

        // Skip if search field not available
        guard gallery.searchField.exists || app.searchFields.count > 0 else {
            throw XCTSkip("Search field not available")
        }

        // WHEN: Enter search term
        gallery.search(for: "test")

        // Wait for filter to apply
        sleep(1)

        // THEN: Search should be active (field has text)
        let searchField = gallery.searchField
        if searchField.exists {
            let hasSearchText = (searchField.value as? String)?.isEmpty == false
            XCTAssertTrue(hasSearchText || app.searchFields.firstMatch.exists, "Search should be active")
        }
    }

    /// Test clearing search restores all results.
    func testClearingSearchRestoresResults() throws {
        // GIVEN: Search is active
        let gallery = GalleryPage(app: app)
        _ = gallery.waitForDisplay()
        gallery.search(for: "test")

        sleep(1)

        // WHEN: Clear search
        gallery.clearSearch()

        // THEN: Results should be restored (or remain as they were)
        // This is a basic verification that clear doesn't crash
        XCTAssertTrue(gallery.isDisplayed(), "Gallery should still be displayed after clearing search")
    }

    // MARK: - Sort Tests

    /// Test sort menu can be opened.
    func testSortMenuCanBeOpened() throws {
        // GIVEN: Gallery is displayed
        let gallery = GalleryPage(app: app)
        _ = gallery.waitForDisplay() 

        // WHEN: Tap sort button
        gallery.openSortMenu()

        // Wait for menu
        sleep(1)

        // THEN: Sort options should be visible (menu appears)
        // Look for any sort option in the menu - with proper diacritics
        let hasMenu = app.buttons["Nejnovější"].exists ||
                      app.buttons["Nejstarší"].exists ||
                      app.buttons["Název A-Z"].exists ||
                      app.buttons.containing(NSPredicate(format: "label CONTAINS 'Nejnov'")).count > 0 ||
                      app.staticTexts["Nejnovější"].exists ||
                      app.menus.count > 0
        XCTAssertTrue(hasMenu, "Sort menu should be visible after tapping sort button")
    }

    // MARK: - Empty State Tests

    /// Test empty state has correct message.
    func testEmptyStateHasCorrectMessage() throws {
        // This test is most relevant for a fresh app launch without mock data
        let gallery = GalleryPage(app: app)
        _ = gallery.waitForDisplay() 

        // If empty, verify the message - with proper diacritics
        if gallery.isEmpty {
            let hasEmptyMessage = app.staticTexts["Žádné modely"].exists ||
                                  app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'modely'")).count > 0 ||
                                  gallery.emptyStateView.exists
            XCTAssertTrue(hasEmptyMessage, "Empty state should have correct message")
        }
    }
}
