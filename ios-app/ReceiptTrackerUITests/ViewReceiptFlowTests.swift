import XCTest

final class ViewReceiptFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A receipt with NO photo attached should not offer a "View Receipt"
    /// swipe action at all.
    func testReceiptWithoutPhotoHasNoViewAction() throws {
        let merchantName = "NoPhoto Merchant \(UUID().uuidString.prefix(8))"

        let app = XCUIApplication()
        app.launch()

        addReceipt(app, merchant: merchantName, totalCost: "3.50")

        let row = app.staticTexts[merchantName]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()

        XCTAssertFalse(app.buttons["viewReceiptButton"].exists)
        // Dismiss the swipe actions so they don't interfere with later taps.
        row.swipeRight()
    }

    /// A receipt seeded with a photo (via the app's UI-test-only seed hook —
    /// see `ReceiptTrackerApp.makeContainer()`) offers "View Receipt", and
    /// tapping it presents the full-size image screen.
    func testViewReceiptShowsFullSizeImage() throws {
        let merchantName = "PhotoTest Merchant \(UUID().uuidString.prefix(8))"

        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SEED_PHOTO_MERCHANT"] = merchantName
        app.launch()

        let row = app.staticTexts[merchantName]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()

        let viewButton = app.buttons["viewReceiptButton"]
        XCTAssertTrue(viewButton.waitForExistence(timeout: 5))
        viewButton.tap()

        XCTAssertTrue(app.images["receiptFullImage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["savePhotoButton"].exists)

        app.buttons["closeReceiptImageButton"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    private func addReceipt(_ app: XCUIApplication, merchant: String, totalCost: String) {
        let addButton = app.buttons["addReceiptButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Receipt list screen did not load")
        addButton.tap()

        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.waitForExistence(timeout: 5))
        merchantField.tap()
        merchantField.typeText(merchant)

        let totalCostField = app.textFields["totalCostField"]
        totalCostField.tap()
        totalCostField.typeText(totalCost)

        app.buttons["saveReceiptButton"].tap()
    }
}
