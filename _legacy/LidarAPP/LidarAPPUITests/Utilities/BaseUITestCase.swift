import XCTest

/// Base class for all UI tests providing common setup, teardown, and utility methods.
///
/// Usage:
/// ```swift
/// final class GalleryUITests: BaseUITestCase {
///     func testGalleryDisplaysEmptyState() {
///         // app is already launched and ready
///         let galleryPage = GalleryPage(app: app)
///         XCTAssertTrue(galleryPage.emptyStateView.exists)
///     }
/// }
/// ```
class BaseUITestCase: XCTestCase {

    // MARK: - Properties

    /// The application under test.
    var app: XCUIApplication!

    /// Configuration for test behavior.
    struct TestConfiguration {
        var launchWithMockMode: Bool = true
        var launchClean: Bool = false
        var continueAfterFailure: Bool = false
        var timeout: TimeInterval = 10
        var additionalLaunchArguments: [String] = []
    }

    /// Override in subclass to customize configuration.
    var configuration: TestConfiguration {
        TestConfiguration()
    }

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = configuration.continueAfterFailure

        app = XCUIApplication()

        // Configure launch arguments
        if configuration.launchWithMockMode {
            app.launchArguments.append("-MockModeEnabled")
            app.launchArguments.append("YES")
        }

        if configuration.launchClean {
            app.launchArguments.append("-ApplePersistenceIgnoreState")
            app.launchArguments.append("YES")
        }

        app.launchArguments.append(contentsOf: configuration.additionalLaunchArguments)

        // Launch the app
        app.launch()

        // Wait for app to settle
        waitForAppToLoad()
    }

    override func tearDownWithError() throws {
        // Capture screenshot on failure
        if testRun?.hasSucceeded == false {
            addScreenshot(name: "FailureScreenshot_\(name)")
        }

        app.terminate()
        app = nil

        try super.tearDownWithError()
    }

    // MARK: - Setup Helpers

    /// Wait for the app to finish loading initial content.
    func waitForAppToLoad(timeout: TimeInterval = 15) {
        // Wait for the main tab bar to appear (gallery tab button)
        let galleryTab = app.buttons[AccessibilityIdentifiers.TabBar.galleryTab]
        let captureButton = app.buttons[AccessibilityIdentifiers.TabBar.captureButton]

        // If accessibility identifiers are not yet applied, wait for generic elements
        let tabBarExists = galleryTab.waitForExistence(timeout: timeout) ||
                          captureButton.waitForExistence(timeout: timeout) ||
                          app.tabBars.firstMatch.waitForExistence(timeout: timeout)

        if !tabBarExists {
            // Fallback: wait for any navigation title or button
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5)
        }
    }

    // MARK: - Screenshot Helpers

    /// Capture and attach a screenshot to test results.
    func addScreenshot(name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Capture screenshot with automatic naming based on test name and timestamp.
    func captureScreenshot(step: String = "") {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            .replacingOccurrences(of: ":", with: "-")
        let stepSuffix = step.isEmpty ? "" : "_\(step)"
        addScreenshot(name: "\(name)\(stepSuffix)_\(timestamp)")
    }

    // MARK: - Navigation Helpers

    /// Navigate to Gallery tab.
    func navigateToGallery() {
        let galleryTab = app.buttons[AccessibilityIdentifiers.TabBar.galleryTab]
        if galleryTab.exists {
            galleryTab.tap()
        } else {
            // Fallback for when accessibility identifiers aren't applied
            app.buttons["Galerie"].firstMatch.tap()
        }
    }

    /// Navigate to Profile tab.
    func navigateToProfile() {
        let profileTab = app.buttons[AccessibilityIdentifiers.TabBar.profileTab]
        if profileTab.exists {
            profileTab.tap()
        } else {
            // Fallback
            app.buttons["Profil"].firstMatch.tap()
        }
    }

    /// Tap the central capture button to open scan mode selector.
    func tapCaptureButton() {
        let captureButton = app.buttons[AccessibilityIdentifiers.TabBar.captureButton]
        if captureButton.exists {
            captureButton.tap()
        } else {
            // Fallback: look for the viewfinder icon button
            app.buttons["viewfinder"].firstMatch.tap()
        }
    }

    /// Open Settings from Profile tab.
    func openSettings() {
        navigateToProfile()

        let settingsButton = app.buttons[AccessibilityIdentifiers.Profile.settingsButton]
        if settingsButton.exists {
            settingsButton.tap()
        } else {
            // Fallback
            app.buttons["Nastaveni"].firstMatch.tap()
        }
    }

    // MARK: - Assertion Helpers

    /// Assert element exists with custom error message.
    func assertExists(_ element: XCUIElement, message: String? = nil, timeout: TimeInterval = 10) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            message ?? "Expected element \(element) to exist"
        )
    }

    /// Assert element does not exist.
    func assertNotExists(_ element: XCUIElement, message: String? = nil) {
        XCTAssertFalse(
            element.exists,
            message ?? "Expected element \(element) to not exist"
        )
    }

    /// Assert element is hittable (visible and tappable).
    func assertHittable(_ element: XCUIElement, message: String? = nil, timeout: TimeInterval = 10) {
        XCTAssertTrue(
            element.waitForHittable(timeout: timeout),
            message ?? "Expected element \(element) to be hittable"
        )
    }

    /// Assert navigation bar title.
    func assertNavigationTitle(_ title: String, timeout: TimeInterval = 5) {
        let navBar = app.navigationBars[title]
        XCTAssertTrue(
            navBar.waitForExistence(timeout: timeout),
            "Expected navigation bar with title '\(title)'"
        )
    }

    // MARK: - Wait Helpers

    /// Wait for element to disappear.
    func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Wait for loading indicator to disappear.
    func waitForLoadingToComplete(timeout: TimeInterval = 30) {
        let loadingIndicator = app.activityIndicators.firstMatch
        if loadingIndicator.exists {
            _ = waitForDisappearance(of: loadingIndicator, timeout: timeout)
        }
    }

    // MARK: - Alert Handling

    /// Dismiss system alert if present (e.g., camera permissions).
    func dismissSystemAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        let okButton = springboard.buttons["OK"]

        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        } else if okButton.waitForExistence(timeout: 1) {
            okButton.tap()
        }
    }

    /// Handle app alert with specific button.
    func dismissAlert(buttonTitle: String) {
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            let button = alert.buttons[buttonTitle]
            if button.exists {
                button.tap()
            }
        }
    }
}
