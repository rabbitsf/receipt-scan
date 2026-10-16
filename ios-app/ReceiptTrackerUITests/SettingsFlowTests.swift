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

        // A previous run may have left another provider selected.
        let claudeSegment = app.segmentedControls["ocrProviderPicker"].buttons["Claude"]
        XCTAssertTrue(claudeSegment.waitForExistence(timeout: 5))
        claudeSegment.tap()

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

    /// Each provider keeps its own key: saving an OpenAI key doesn't
    /// replace the Claude one, and switching back shows Claude's key again.
    /// The selected provider also survives a relaunch.
    func testSwitchingProvidersKeepsSeparateKeys() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["settingsButton"].tap()
        let picker = app.segmentedControls["ocrProviderPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let apiKeyField = app.secureTextFields["apiKeyField"]
        let removeKeyButton = app.buttons["removeAPIKeyButton"]

        // Start from a clean slate for both providers.
        for provider in ["OpenAI", "Claude"] {
            picker.buttons[provider].tap()
            if removeKeyButton.waitForExistence(timeout: 2) { removeKeyButton.tap() }
        }

        apiKeyField.tap()
        apiKeyField.typeText("sk-ant-uitest-claude")
        app.buttons["saveAPIKeyButton"].tap()
        XCTAssertTrue(app.staticTexts["Saved."].waitForExistence(timeout: 5))

        picker.buttons["OpenAI"].tap()
        XCTAssertFalse(removeKeyButton.waitForExistence(timeout: 2), "OpenAI must not inherit Claude's key")
        apiKeyField.tap()
        apiKeyField.typeText("sk-uitest-openai")
        app.buttons["saveAPIKeyButton"].tap()
        XCTAssertTrue(app.staticTexts["Saved."].waitForExistence(timeout: 5))

        picker.buttons["Gemini"].tap()
        XCTAssertFalse(removeKeyButton.waitForExistence(timeout: 2), "Gemini has no key saved")

        picker.buttons["Claude"].tap()
        XCTAssertTrue(removeKeyButton.waitForExistence(timeout: 5), "Claude's key must survive saving an OpenAI key")

        picker.buttons["OpenAI"].tap()
        XCTAssertTrue(removeKeyButton.waitForExistence(timeout: 5))
        app.buttons["Close"].tap()

        app.terminate()
        app.launch()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.buttons["OpenAI"].isSelected, "Selected provider should persist across relaunch")

        // Clean up: remove both keys and leave Claude selected.
        removeKeyButton.tap()
        picker.buttons["Claude"].tap()
        XCTAssertTrue(removeKeyButton.waitForExistence(timeout: 5))
        removeKeyButton.tap()
    }
}
