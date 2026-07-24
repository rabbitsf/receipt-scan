import XCTest

final class EditDeleteReceiptFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Add a receipt, tap it to edit, change the merchant, save, and confirm
    /// the list reflects the update (not a duplicate row).
    func testEditReceiptUpdatesList() throws {
        let originalName = "Edit Test Original"
        let updatedName = "Edit Test Updated"

        let app = XCUIApplication()
        app.launch()

        addReceipt(app, merchant: originalName, totalCost: "10.00")

        let originalRow = app.staticTexts[originalName]
        XCTAssertTrue(originalRow.waitForExistence(timeout: 10))
        originalRow.tap()

        XCTAssertTrue(app.navigationBars["Edit Receipt"].waitForExistence(timeout: 5))

        let merchantField = app.textFields["merchantField"]
        XCTAssertEqual(merchantField.value as? String, originalName)
        merchantField.tap()
        // Plain SwiftUI TextField has no built-in clear button — delete the
        // existing characters one by one before typing the replacement.
        let deleteKeys = String(repeating: XCUIKeyboardKey.delete.rawValue, count: originalName.count)
        merchantField.typeText(deleteKeys)
        merchantField.typeText(updatedName)

        app.buttons["saveReceiptButton"].tap()

        XCTAssertTrue(app.staticTexts[updatedName].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[originalName].exists)
    }

    /// Add a receipt, swipe-to-delete it, confirm it's gone.
    func testDeleteReceiptRemovesFromList() throws {
        // Unique per run — leftover rows from earlier runs against this
        // same on-device store would otherwise make `row` (below) ambiguous.
        let merchantName = "Delete Test Merchant \(UUID().uuidString.prefix(8))"

        let app = XCUIApplication()
        app.launch()

        addReceipt(app, merchant: merchantName, totalCost: "5.00")

        let row = app.staticTexts[merchantName]
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        // Swipe left on the row to reveal the Delete action. Swiping on the
        // merchant text itself (rather than a specific container type like
        // `.buttons`) is robust to how the row happens to be structured —
        // it changed from a `Button` wrapper to a plain `HStack` +
        // `onTapGesture` in Slice 7 (for bulk-select), which broke a
        // `.buttons.containing(...)` query that assumed the old structure.
        row.swipeLeft()
        app.buttons["Delete"].tap()

        XCTAssertTrue(row.waitForNonExistence(timeout: 10))
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

private extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
