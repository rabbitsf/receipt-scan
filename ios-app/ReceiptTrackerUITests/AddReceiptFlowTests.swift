import XCTest

final class AddReceiptFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Exercises the real vertical slice: launch → tap Add → fill form →
    /// Save → confirm the new receipt appears in the list, persisted to the
    /// on-device SwiftData store (fully standalone, no backend involved).
    func testAddReceiptAppearsInList() throws {
        let merchantName = "UITest Verify Merchant"

        let app = XCUIApplication()
        app.launch()

        let addButton = app.buttons["addReceiptButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Receipt list screen did not load")

        addButton.tap()

        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.waitForExistence(timeout: 5))
        merchantField.tap()
        merchantField.typeText(merchantName)

        let totalCostField = app.textFields["totalCostField"]
        totalCostField.tap()
        totalCostField.typeText("12.34")

        app.buttons["saveReceiptButton"].tap()

        let newRow = app.staticTexts[merchantName]
        XCTAssertTrue(newRow.waitForExistence(timeout: 10), "New receipt did not appear in the list after saving")
    }
}
