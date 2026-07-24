import XCTest

final class CategoryNoteFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Add a receipt with a predefined category and a note, confirm both
    /// are pre-filled correctly when reopening it for edit (proves they
    /// were actually persisted to the model, not just cosmetic form state).
    func testPredefinedCategoryAndNotePersistThroughEdit() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        let merchantName = "CategoryTest Predefined Merchant"

        app.buttons["addReceiptButton"].tap()
        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.waitForExistence(timeout: 10))
        merchantField.tap()
        merchantField.typeText(merchantName)
        app.textFields["totalCostField"].tap()
        app.textFields["totalCostField"].typeText("9.99")

        app.buttons["categoryPicker"].tap()
        app.buttons["Travel"].tap()

        let noteField = app.textFields["noteField"]
        noteField.tap()
        noteField.typeText("Reimbursable")

        app.buttons["saveReceiptButton"].tap()

        // Confirm it shows in the list with the category.
        // `.firstMatch` since repeated test runs against the same
        // on-device store can leave more than one row with this name.
        let row = app.staticTexts[merchantName].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["· Travel"].firstMatch.waitForExistence(timeout: 5))

        // Reopen for edit, confirm both fields were really persisted.
        // (Checking the picker's visible selected-value text, not
        // `.value` — SwiftUI's menu-style Picker doesn't reliably expose
        // the selection through XCUITest's `.value` property, even though
        // the underlying model/binding is correct — already confirmed
        // separately by the list row showing "· Travel" right after save.)
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit Receipt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["categoryPicker"].staticTexts["Travel"].waitForExistence(timeout: 5))
        XCTAssertEqual(noteField.value as? String, "Reimbursable")
    }

    /// Add a receipt with a CUSTOM category (not in the predefined list),
    /// confirm it's persisted and that the category picker/filter now
    /// offers it as a selectable option elsewhere (merged in-use category).
    func testCustomCategoryPersistsAndAppearsInFilterOptions() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        let merchantName = "CategoryTest Custom Merchant"
        let customCategory = "ZZZTestCustomCategory"

        app.buttons["addReceiptButton"].tap()
        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.waitForExistence(timeout: 10))
        merchantField.tap()
        merchantField.typeText(merchantName)
        app.textFields["totalCostField"].tap()
        app.textFields["totalCostField"].typeText("4.50")

        app.buttons["categoryPicker"].tap()
        app.buttons["Custom category…"].tap()

        let customField = app.textFields["customCategoryField"]
        XCTAssertTrue(customField.waitForExistence(timeout: 5))
        customField.tap()
        customField.typeText(customCategory)

        app.buttons["saveReceiptButton"].tap()

        XCTAssertTrue(app.staticTexts[merchantName].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["· \(customCategory)"].waitForExistence(timeout: 5))

        // Confirm the custom category is now offered in the filter sheet.
        app.buttons["filterButton"].tap()
        app.buttons["categoryFilterPicker"].tap()
        XCTAssertTrue(app.buttons[customCategory].waitForExistence(timeout: 5))
    }
}
