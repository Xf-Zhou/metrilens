import XCTest

final class MetrilensUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["METRILENS_UI_TESTING"] = "1"
        app.launchEnvironment["METRILENS_UI_TEST_RESET"] = "1"
        app.launchEnvironment["METRILENS_UI_TEST_LANGUAGE"] = "simplifiedChinese"
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    func testMenuBarPopoverSettingsAndLanguageFlow() {
        app.launch()

        let statusItem = app.statusItems["metrilens.statusItem"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()

        let settingsButton = app.buttons["metrilens.popover.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        XCTAssertTrue(settingsButton.waitUntilHittable(timeout: 3))
        XCTAssertTrue(app.buttons["metrilens.popover.about"].exists)
        settingsButton.click()

        let chineseWindow = app.windows["Metrilens 设置"]
        XCTAssertTrue(chineseWindow.waitForExistence(timeout: 3))
        let languagePopup = app.popUpButtons["metrilens.preferences.language"]
        XCTAssertTrue(languagePopup.exists)
        languagePopup.click()
        app.menuItems["English"].click()

        XCTAssertTrue(app.windows["Metrilens Settings"].waitForExistence(timeout: 3))
        XCTAssertEqual(languagePopup.value as? String, "English")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Metrilens English Preferences"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitUntilHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.exists && element.isHittable
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: self
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
