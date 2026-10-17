import XCTest

/// Covers what's testable WITHOUT signing in to a real Google account.
/// `project.yml` carries the real `GIDClientID`, so tapping Connect starts
/// the genuine Google sign-in — iOS first asks permission via a system
/// "Wants to Use google.com to Sign In" alert. These tests stop at that
/// alert (Cancel) rather than driving Google's web sign-in, which can't be
/// automated reliably and would need real credentials. The full OAuth flow
/// and a live Drive upload are verified manually on a real device.
final class GoogleDriveFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Tapping Connect hands off to Google sign-in (the system permission
    /// alert appears); cancelling it leaves the section disconnected, with
    /// Connect offered again and a status message explaining what happened.
    func testConnectToGoogleDriveStartsSignInAndCancelLeavesDisconnected() throws {
        let app = XCUIApplication.receiptTracker()
        app.terminate()
        app.launch()

        app.buttons["settingsButton"].tap()
        let connectButton = app.buttons["connectDriveButton"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 5))
        connectButton.tap()

        // The permission alert belongs to SpringBoard, not the app.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let signInAlert = springboard.alerts.firstMatch
        XCTAssertTrue(signInAlert.waitForExistence(timeout: 10), "Expected Google sign-in to start (system sign-in alert)")
        XCTAssertTrue(signInAlert.label.contains("Sign In"), "Unexpected alert: \(signInAlert.label)")
        // A plain `.tap()` on this SpringBoard alert's buttons is silently
        // ignored (the alert stays up and sign-in never ends); tapping the
        // button's coordinate does register.
        signInAlert.buttons["Cancel"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let status = app.staticTexts["driveStatusMessage"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.localizedCaseInsensitiveContains("cancel"), "Expected a cancelled message, got: \(status.label)")
        XCTAssertTrue(connectButton.waitForExistence(timeout: 5))
        XCTAssertTrue(connectButton.isEnabled, "Connect should be offered again after cancelling")
        XCTAssertFalse(app.buttons["disconnectDriveButton"].exists)
    }

    /// A receipt seeded with a photo (same UI-test-only seed hook as
    /// `ViewReceiptFlowTests`) offers "Upload to Drive" in the full-size
    /// image view; tapping it while not connected shows the
    /// not-connected message rather than attempting a network call.
    func testUploadToDriveFromImageViewShowsNotConnectedMessage() throws {
        let merchantName = "DriveUploadTest Merchant \(UUID().uuidString.prefix(8))"

        let app = XCUIApplication.receiptTracker()
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

        let app = XCUIApplication.receiptTracker()
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
