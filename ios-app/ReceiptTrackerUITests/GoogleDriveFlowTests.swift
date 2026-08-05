import XCTest

/// Covers what's testable WITHOUT live Google credentials: `GIDClientID` in
/// this checked-out project is a placeholder (see `project.yml`), so
/// `GoogleDriveAuth.signIn` always fails fast with `.missingClientID`
/// before any network/UI presentation — that's a real, exercisable code
/// path, not a mock. The actual OAuth flow + live Drive upload need a
/// manual smoke test once a real Client ID is configured (see the plan
/// file / setup instructions).
final class GoogleDriveFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConnectToGoogleDriveShowsNotConfiguredMessageWithPlaceholderClientID() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        app.buttons["settingsButton"].tap()
        let connectButton = app.buttons["connectDriveButton"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 5))
        connectButton.tap()

        let status = app.staticTexts["driveStatusMessage"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("not configured"), "Expected a not-configured message, got: \(status.label)")

        // Connect button should still be offered — sign-in never actually
        // succeeded/started, so the section shouldn't have flipped to the
        // "Disconnect" (connected) state.
        XCTAssertTrue(app.buttons["connectDriveButton"].exists)
        XCTAssertFalse(app.buttons["disconnectDriveButton"].exists)
    }

    /// A receipt seeded with a photo (same UI-test-only seed hook as
    /// `ViewReceiptFlowTests`) offers "Upload to Drive" in the full-size
    /// image view; tapping it while not connected shows the
    /// not-connected message rather than attempting a network call.
    func testUploadToDriveFromImageViewShowsNotConnectedMessage() throws {
        let merchantName = "DriveUploadTest Merchant \(UUID().uuidString.prefix(8))"

        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SEED_PHOTO_MERCHANT"] = merchantName
        app.launch()

        let row = app.staticTexts[merchantName]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        let viewButton = app.buttons["viewReceiptButton"]
        XCTAssertTrue(viewButton.waitForExistence(timeout: 5))
        viewButton.tap()

        let uploadButton = app.buttons["uploadToDriveButton"]
        XCTAssertTrue(uploadButton.waitForExistence(timeout: 5))
        uploadButton.tap()

        let status = app.staticTexts["imageActionStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Not connected"), "Expected a not-connected message, got: \(status.label)")

        app.buttons["closeReceiptImageButton"].tap()
    }

    /// Selecting one or more receipts in the list offers a bulk "Upload"
    /// action alongside Delete/Export; tapping it while not connected shows
    /// a "Google Drive" alert rather than attempting to upload anything.
    func testBulkUploadFromSelectionShowsNotConnectedAlert() throws {
        let merchantName = "DriveBulkTest Merchant \(UUID().uuidString.prefix(8))"

        let app = XCUIApplication()
        app.terminate()
        app.launch()

        let addButton = app.buttons["addReceiptButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.tap()
        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.waitForExistence(timeout: 5))
        merchantField.tap()
        merchantField.typeText(merchantName)
        app.textFields["totalCostField"].tap()
        app.textFields["totalCostField"].typeText("9.99")
        app.buttons["saveReceiptButton"].tap()

        let row = app.staticTexts[merchantName]
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        app.buttons["selectButton"].tap()
        row.tap()

        let uploadButton = app.buttons["bulkUploadToDriveButton"]
        XCTAssertTrue(uploadButton.waitForExistence(timeout: 5))
        uploadButton.tap()

        XCTAssertTrue(app.alerts["Google Drive"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts["Google Drive"].staticTexts["Not connected to Google Drive. Connect in Settings first."].exists)
        app.alerts["Google Drive"].buttons["OK"].tap()
    }
}
