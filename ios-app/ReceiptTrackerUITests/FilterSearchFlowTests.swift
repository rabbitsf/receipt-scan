import XCTest

final class FilterSearchFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Adds two receipts with distinct, known merchant names and searches
    /// for one of them — confirms the search bar actually filters the list
    /// down rather than just cosmetically existing.
    func testSearchFiltersListToMatchingMerchant() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        addReceipt(app, merchant: "FilterTest Alpha Merchant", totalCost: "1.00")
        addReceipt(app, merchant: "FilterTest Beta Merchant", totalCost: "2.00")

        XCTAssertTrue(app.staticTexts["FilterTest Alpha Merchant"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["FilterTest Beta Merchant"].waitForExistence(timeout: 5))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Alpha Merchant")

        XCTAssertTrue(app.staticTexts["FilterTest Alpha Merchant"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["FilterTest Beta Merchant"].exists)

        // Clear search to restore full list, cleanup, don't leak state to other tests.
        searchField.buttons["Clear text"].tap()
    }

    /// Adds a receipt, sets a Year filter that excludes it (a year other
    /// than today's), confirms it disappears with the "no receipts match"
    /// message, then clears filters and confirms it reappears.
    func testYearFilterExcludesAndClearFiltersRestores() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        addReceipt(app, merchant: "FilterTest Year Merchant", totalCost: "3.00")
        XCTAssertTrue(app.staticTexts["FilterTest Year Merchant"].waitForExistence(timeout: 10))

        app.buttons["filterButton"].tap()
        let yearPicker = app.buttons["yearFilterPicker"]
        XCTAssertTrue(yearPicker.waitForExistence(timeout: 5))
        yearPicker.tap()

        let oldYear = String(Calendar.current.component(.year, from: Date()) - 5)
        app.buttons[oldYear].tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["No receipts match the current filters"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["FilterTest Year Merchant"].exists)

        app.buttons["filterButton"].tap()
        app.buttons["clearFiltersButton"].tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["FilterTest Year Merchant"].waitForExistence(timeout: 5))
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
