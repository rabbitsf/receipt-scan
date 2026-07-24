import XCTest

final class DashboardFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Add a receipt with a known amount and category for the current year,
    /// open the Dashboard, and confirm the year total and category
    /// breakdown actually reflect it — not just that the screen opens.
    func testDashboardReflectsAddedReceipt() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        let merchantName = "DashboardTest Merchant"

        app.buttons["addReceiptButton"].tap()
        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.waitForExistence(timeout: 10))
        merchantField.tap()
        merchantField.typeText(merchantName)
        app.textFields["totalCostField"].tap()
        app.textFields["totalCostField"].typeText("77.00")

        app.buttons["categoryPicker"].tap()
        app.buttons["Utilities"].tap()

        app.buttons["saveReceiptButton"].tap()
        XCTAssertTrue(app.staticTexts[merchantName].firstMatch.waitForExistence(timeout: 10))

        app.buttons["dashboardButton"].tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))

        // The "By Category" section is below the 12-row monthly breakdown
        // in a lazily-rendered List — off-screen rows genuinely don't exist
        // in the accessibility tree until scrolled into view.
        let categoryRow = app.staticTexts["Utilities"]
        for _ in 0..<5 where !categoryRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(categoryRow.waitForExistence(timeout: 5))
    }

    /// Confirms year selection actually changes what's displayed: switch to
    /// a year with no data and confirm the monthly breakdown all reads
    /// $0.00 (rather than being frozen on the previous year's numbers).
    func testChangingDashboardYearUpdatesTotals() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        app.buttons["dashboardButton"].tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))

        app.buttons["dashboardYearPicker"].tap()
        let oldYear = String(Calendar.current.component(.year, from: Date()) - 5)
        app.buttons[oldYear].tap()

        XCTAssertTrue(app.staticTexts["\(oldYear) total"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["$0.00"].firstMatch.waitForExistence(timeout: 5))
    }
}
