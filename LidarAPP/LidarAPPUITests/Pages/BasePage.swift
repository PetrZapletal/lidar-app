import XCTest

/// Base class for all Page Objects providing common functionality.
///
/// The Page Object pattern encapsulates the UI structure and interactions
/// for a specific screen, making tests more maintainable and readable.
///
/// Usage:
/// ```swift
/// class GalleryPage: BasePage {
///     var scanGrid: XCUIElement {
///         app.scrollViews[AccessibilityIdentifiers.Gallery.scanGrid]
///     }
///     // ...
/// }
/// ```
class BasePage {

    // MARK: - Properties

    /// The application instance
    let app: XCUIApplication

    /// Default timeout for element waits
    var defaultTimeout: TimeInterval = 10

    // MARK: - Initialization

    /// Initialize with application instance.
    /// - Parameter app: The XCUIApplication instance
    required init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Common Elements

    /// Navigation bar for current screen
    var navigationBar: XCUIElement {
        app.navigationBars.firstMatch
    }

    /// Back button in navigation bar
    var backButton: XCUIElement {
        app.navigationBars.buttons.firstMatch
    }

    /// Loading indicator
    var loadingIndicator: XCUIElement {
        app.activityIndicators.firstMatch
    }

    /// First alert on screen
    var alert: XCUIElement {
        app.alerts.firstMatch
    }

    /// First sheet on screen
    var sheet: XCUIElement {
        app.sheets.firstMatch
    }

    // MARK: - Verification

    /// Verify that the page is currently displayed.
    /// Override in subclass to provide specific verification.
    func isDisplayed() -> Bool {
        // Default implementation - override in subclass
        return true
    }

    /// Wait for page to be displayed.
    @discardableResult
    func waitForDisplay(timeout: TimeInterval? = nil) -> Bool {
        let timeoutValue = timeout ?? defaultTimeout
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeoutValue {
            if isDisplayed() {
                return true
            }
            usleep(100_000) // 0.1 seconds
        }

        return isDisplayed()
    }

    // MARK: - Navigation

    /// Navigate back using navigation bar back button.
    func navigateBack() {
        if backButton.exists {
            backButton.tap()
        }
    }

    // MARK: - Loading State

    /// Check if page is currently loading.
    var isLoading: Bool {
        loadingIndicator.exists
    }

    /// Wait for loading to complete.
    @discardableResult
    func waitForLoadingToComplete(timeout: TimeInterval = 30) -> Bool {
        if !loadingIndicator.exists {
            return true
        }

        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: loadingIndicator)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    // MARK: - Alert Handling

    /// Check if alert is displayed.
    var isAlertDisplayed: Bool {
        alert.exists
    }

    /// Get alert title.
    var alertTitle: String? {
        guard isAlertDisplayed else { return nil }
        return alert.label
    }

    /// Dismiss alert with specified button.
    func dismissAlert(button: String) {
        if isAlertDisplayed {
            let alertButton = alert.buttons[button]
            if alertButton.exists {
                alertButton.tap()
            }
        }
    }

    // MARK: - Utility Methods

    /// Wait for an element to exist.
    @discardableResult
    func waitFor(_ element: XCUIElement, timeout: TimeInterval? = nil) -> Bool {
        let timeoutValue = timeout ?? defaultTimeout
        return element.waitForExistence(timeout: timeoutValue)
    }

    /// Wait for an element and tap it.
    @discardableResult
    func waitAndTap(_ element: XCUIElement, timeout: TimeInterval? = nil) -> Bool {
        let timeoutValue = timeout ?? defaultTimeout
        if element.waitForExistence(timeout: timeoutValue) {
            element.tap()
            return true
        }
        return false
    }

    /// Scroll to find element in scroll view.
    @discardableResult
    func scrollTo(_ element: XCUIElement, in scrollView: XCUIElement, direction: XCUIElement.SwipeDirection = .up, maxSwipes: Int = 10) -> Bool {
        return element.scrollToElement(in: scrollView, direction: direction, maxSwipes: maxSwipes)
    }

    /// Type text into a text field.
    func typeText(_ text: String, in textField: XCUIElement, clearFirst: Bool = true) {
        if waitFor(textField) {
            textField.tap()
            if clearFirst {
                textField.clearAndTypeText(text)
            } else {
                textField.typeText(text)
            }
        }
    }

    /// Take screenshot with given name.
    func takeScreenshot(named name: String) -> XCTAttachment {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
