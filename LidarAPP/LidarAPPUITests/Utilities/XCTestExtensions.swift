import XCTest

// MARK: - XCUIElement Extensions

extension XCUIElement {

    /// Wait for element to exist and then tap it.
    /// - Parameters:
    ///   - timeout: Maximum time to wait before tapping
    /// - Returns: True if tap was successful
    @discardableResult
    func waitAndTap(timeout: TimeInterval = 10) -> Bool {
        guard waitForExistence(timeout: timeout) else {
            XCTFail("Element \(self) did not appear within \(timeout) seconds")
            return false
        }
        tap()
        return true
    }

    /// Wait for element to be hittable (visible and tappable).
    /// - Parameters:
    ///   - timeout: Maximum time to wait
    /// - Returns: True if element becomes hittable
    func waitForHittable(timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Clear text field and type new text.
    /// - Parameter text: Text to enter
    func clearAndTypeText(_ text: String) {
        guard let stringValue = self.value as? String else {
            tap()
            typeText(text)
            return
        }

        tap()

        // Select all and delete
        if !stringValue.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
            typeText(deleteString)
        }

        typeText(text)
    }

    /// Check if element contains specific text (case-insensitive).
    func containsText(_ text: String) -> Bool {
        let label = self.label.lowercased()
        let value = (self.value as? String)?.lowercased() ?? ""
        let searchText = text.lowercased()
        return label.contains(searchText) || value.contains(searchText)
    }

    /// Scroll to element if it's not visible.
    func scrollToElement(in scrollView: XCUIElement, direction: SwipeDirection = .up, maxSwipes: Int = 10) -> Bool {
        var swipeCount = 0
        while !self.isHittable && swipeCount < maxSwipes {
            switch direction {
            case .up:
                scrollView.swipeUp()
            case .down:
                scrollView.swipeDown()
            case .left:
                scrollView.swipeLeft()
            case .right:
                scrollView.swipeRight()
            }
            swipeCount += 1
        }
        return self.isHittable
    }

    enum SwipeDirection {
        case up, down, left, right
    }
}

// MARK: - XCUIApplication Extensions

extension XCUIApplication {

    /// Launch app with mock mode enabled for simulator testing.
    func launchWithMockMode() {
        launchArguments.append("-MockModeEnabled")
        launchArguments.append("YES")
        launch()
    }

    /// Launch app in clean state (reset user defaults).
    func launchClean() {
        launchArguments.append("-ApplePersistenceIgnoreState")
        launchArguments.append("YES")
        launch()
    }

    /// Launch app with specific launch arguments.
    func launch(with arguments: [String]) {
        launchArguments.append(contentsOf: arguments)
        launch()
    }

    /// Take a screenshot and attach to test results.
    func takeScreenshot(named name: String) -> XCTAttachment {
        let screenshot = self.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }

    /// Wait for app to become idle.
    func waitForAppToIdle(timeout: TimeInterval = 5) {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if !self.state.rawValue.description.contains("Running") {
                usleep(100_000) // 0.1 seconds
            } else {
                break
            }
        }
    }
}

// MARK: - XCTestCase Extensions

extension XCTestCase {

    /// Wait for a condition to become true.
    /// - Parameters:
    ///   - timeout: Maximum time to wait
    ///   - condition: Closure that returns true when condition is met
    /// - Returns: True if condition was met within timeout
    @discardableResult
    func wait(timeout: TimeInterval = 10, for condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Add screenshot attachment to test results.
    func addScreenshot(app: XCUIApplication, name: String) {
        let attachment = app.takeScreenshot(named: name)
        add(attachment)
    }

    /// Assert that an element eventually contains expected text.
    func assertEventuallyContains(
        element: XCUIElement,
        text: String,
        timeout: TimeInterval = 10,
        message: String? = nil
    ) {
        let predicate = NSPredicate { _, _ in
            element.containsText(text)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)

        if result != .completed {
            XCTFail(message ?? "Element did not contain '\(text)' within \(timeout) seconds")
        }
    }
}

// MARK: - String Constants for Tests

extension String {
    // Common button labels in the app (Czech localization)
    static let cancelButton = "Zrusit"
    static let doneButton = "Hotovo"
    static let saveButton = "Ulozit"
    static let deleteButton = "Smazat"
    static let closeButton = "Zavrit"
    static let settingsButton = "Nastaveni"
}
