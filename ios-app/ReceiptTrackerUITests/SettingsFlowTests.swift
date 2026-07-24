import XCTest

final class SettingsFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Save a key via the Settings screen, fully terminate and relaunch the
    /// app, then confirm the key field still shows a stored value — proving
    /// it round-trips through the real Keychain across process lifetimes,
    /// not just in-memory state.
    func testAPIKeySurvivesAppRelaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let apiKeyField = app.secureTextFields["apiKeyField"]
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 5))
        apiKeyField.tap()
        apiKeyField.typeText("sk-ant-uitest-fake-key")

        app.buttons["saveAPIKeyButton"].tap()
        XCTAssertTrue(app.staticTexts["Saved."].waitForExistence(timeout: 5))

        app.buttons["Close"].tap()

        app.terminate()
        app.launch()

        settingsButton.tap()
        let reloadedField = app.secureTextFields["apiKeyField"]
        XCTAssertTrue(reloadedField.waitForExistence(timeout: 5))
        let value = reloadedField.value as? String ?? ""
        XCTAssertFalse(value.isEmpty, "API key field should show a masked value after relaunch")

        // Clean up so this test doesn't leak state into other test runs.
        app.buttons["removeAPIKeyButton"].tap()
    }
}
