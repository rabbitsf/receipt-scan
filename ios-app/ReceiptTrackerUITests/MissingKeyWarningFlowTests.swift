import XCTest

/// The "No API Key" popup shown at launch. Each test forces the popup on
/// (`-ocrKeyWarningDismissed NO` overrides whatever an earlier run stored)
/// and selects Gemini, which no UI test ever saves a key for — so the
/// popup's condition holds regardless of leftover simulator state.
final class MissingKeyWarningFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp(forceWarning: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ocrProvider", "gemini"]
        if forceWarning {
            app.launchArguments += ["-ocrKeyWarningDismissed", "NO"]
        }
        return app
    }

    func testMissingKeyWarningAddKeyOpensSettings() throws {
        let app = makeApp(forceWarning: true)
        app.terminate()
        app.launch()

        let alert = app.alerts["No API Key"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Claude, OpenAI, or Gemini")).firstMatch.exists)
        alert.buttons["Add Key"].tap()

        let picker = app.segmentedControls["ocrProviderPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Add Key should open Settings")
        XCTAssertTrue(picker.buttons["Gemini"].isSelected)
        XCTAssertTrue(app.secureTextFields["apiKeyField"].exists)
    }

    func testMissingKeyWarningNotNowDismissesAndShowsAgainNextLaunch() throws {
        let app = makeApp(forceWarning: true)
        app.terminate()
        app.launch()

        let alert = app.alerts["No API Key"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Not Now"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["addReceiptButton"].isHittable, "The app is usable without a key")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.alerts["No API Key"].waitForExistence(timeout: 10), "Not Now only dismisses this launch")
    }

    /// "Don't Show Again" is persisted: launching again WITHOUT the
    /// override argument reads the stored value, so no popup.
    func testMissingKeyWarningDontShowAgainPersistsAcrossLaunches() throws {
        let app = makeApp(forceWarning: true)
        app.terminate()
        app.launch()

        let alert = app.alerts["No API Key"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Don't Show Again"].tap()

        app.terminate()
        let relaunched = makeApp(forceWarning: false)
        relaunched.launch()
        XCTAssertTrue(relaunched.buttons["addReceiptButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(relaunched.alerts["No API Key"].waitForExistence(timeout: 3))
    }
}
