import XCTest

final class GroupFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Add a receipt with a brand-new group (via "New group…", there's no
    /// predefined list to pick from), confirm it's persisted (shows on the
    /// list row) and subsequently offered as a selectable option in the
    /// Filter sheet's group picker — mirrors
    /// `CategoryNoteFlowTests.testCustomCategoryPersistsAndAppearsInFilterOptions`.
    func testGroupPersistsAndAppearsInFilterOptions() throws {
        let app = XCUIApplication.receiptTracker()
        app.terminate()
        app.launch()

        let merchantName = "GroupTest Merchant \(UUID().uuidString.prefix(8))"
        let groupName = "ZZZTestGroup Business Trip"

        app.buttons["addReceiptButton"].tap()
        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.waitForExistence(timeout: 10))
        merchantField.tap()
        merchantField.typeText(merchantName)
        app.textFields["totalCostField"].tap()
        app.textFields["totalCostField"].typeText("42.00")

        app.buttons["groupPicker"].tap()
        // "New group…" is always the LAST option in the in-use-groups
        // list, same accumulated-options fragility documented for
        // "Custom category…" elsewhere in this test target — swipe up a
        // few times before giving up.
        let newGroupOption = app.buttons["New group…"]
        for _ in 0..<5 where !newGroupOption.exists {
            app.swipeUp()
        }
        XCTAssertTrue(newGroupOption.waitForExistence(timeout: 5))
        newGroupOption.tap()

        let customField = app.textFields["customGroupField"]
        XCTAssertTrue(customField.waitForExistence(timeout: 5))
        customField.tap()
        customField.typeText(groupName)

        app.buttons["saveReceiptButton"].tap()

        XCTAssertTrue(app.staticTexts[merchantName].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[groupName].waitForExistence(timeout: 5))

        // Confirm the group is now offered in the filter sheet.
        app.buttons["filterButton"].tap()
        app.buttons["groupFilterPicker"].tap()
        let groupOption = app.buttons[groupName]
        for _ in 0..<5 where !groupOption.exists {
            app.swipeUp()
        }
        XCTAssertTrue(groupOption.waitForExistence(timeout: 5))
    }

    /// Add two receipts with different groups (one with none), filter by
    /// one specific group via the Filter sheet, confirm the list scopes to
    /// only the matching receipt.
    func testGroupFilterScopesListToMatchingReceipts() throws {
        let app = XCUIApplication.receiptTracker()
        app.terminate()
        app.launch()

        let runID = String(UUID().uuidString.prefix(8))
        let groupName = "ZZZTestGroup Filter \(runID)"
        let matchingMerchant = "GroupFilterTest Matching \(runID)"
        let otherMerchant = "GroupFilterTest Other \(runID)"

        addReceiptWithGroup(app, merchant: matchingMerchant, totalCost: "10.00", group: groupName)
        addReceiptWithoutGroup(app, merchant: otherMerchant, totalCost: "20.00")

        XCTAssertTrue(app.staticTexts[matchingMerchant].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[otherMerchant].waitForExistence(timeout: 5))

        app.buttons["filterButton"].tap()
        app.buttons["groupFilterPicker"].tap()
        let groupOption = app.buttons[groupName]
        for _ in 0..<5 where !groupOption.exists {
            app.swipeUp()
        }
        XCTAssertTrue(groupOption.waitForExistence(timeout: 5))
        groupOption.tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts[matchingMerchant].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[otherMerchant].exists)
    }

    private func addReceiptWithGroup(_ app: XCUIApplication, merchant: String, totalCost: String, group: String) {
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

        app.buttons["groupPicker"].tap()
        let newGroupOption = app.buttons["New group…"]
        for _ in 0..<5 where !newGroupOption.exists {
            app.swipeUp()
        }
        XCTAssertTrue(newGroupOption.waitForExistence(timeout: 5))
        newGroupOption.tap()
        let customField = app.textFields["customGroupField"]
        XCTAssertTrue(customField.waitForExistence(timeout: 5))
        customField.tap()
        customField.typeText(group)

        app.buttons["saveReceiptButton"].tap()
    }

    private func addReceiptWithoutGroup(_ app: XCUIApplication, merchant: String, totalCost: String) {
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
