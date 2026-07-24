import XCTest

final class BulkSelectExportFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Add two receipts, enter select mode, select one, bulk-delete it,
    /// confirm only that one is gone and the other survives.
    func testBulkSelectAndDeleteRemovesOnlySelectedReceipt() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        // Unique per test run (not just per test) so leftover data from
        // earlier runs against this same on-device store can't collide.
        let runID = UUID().uuidString.prefix(8)
        let keepName = "BulkTest Keep Merchant \(runID)"
        let deleteName = "BulkTest Delete Merchant \(runID)"
        addReceipt(app, merchant: keepName, totalCost: "1.00")
        addReceipt(app, merchant: deleteName, totalCost: "2.00")

        XCTAssertTrue(app.staticTexts[keepName].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[deleteName].waitForExistence(timeout: 5))

        app.buttons["selectButton"].tap()

        // In edit/selection mode, tapping a row toggles selection instead
        // of opening it for editing.
        app.staticTexts[deleteName].firstMatch.tap()

        XCTAssertTrue(app.buttons["bulkDeleteButton"].waitForExistence(timeout: 5))
        app.buttons["bulkDeleteButton"].tap()

        XCTAssertTrue(app.staticTexts[keepName].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[deleteName].exists)
    }

    /// Tapping Export (no selection) presents some share interface — proves
    /// the CSV was generated and handed off successfully. Not attempting to
    /// complete an actual share action or inspect the system share sheet's
    /// internals (same fragility class as automating the Photos picker,
    /// per the Slice 3/4 lesson) — presence of the sheet is the meaningful,
    /// reliable check here; the CSV content itself is covered by
    /// `ReceiptCSVExporterTests` (unit, no UI needed).
    func testExportButtonPresentsShareSheet() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        addReceipt(app, merchant: "ExportTest Merchant", totalCost: "5.00")
        XCTAssertTrue(app.staticTexts["ExportTest Merchant"].waitForExistence(timeout: 10))

        app.buttons["exportButton"].tap()

        // "ActivityListView" is UIActivityViewController's own internal
        // accessibility identifier for its populated content list — this is
        // the ONLY reliable signal that real share activities actually
        // rendered. Earlier versions of this assertion OR'd in
        // `app.sheets.firstMatch` / `app.collectionViews.firstMatch` as
        // fallbacks, which was a real bug in the test itself: SwiftUI's
        // List is backed by a UICollectionView, so `collectionViews.
        // firstMatch` matched the app's OWN receipt list underneath a
        // still-blank sheet and made the test pass even while
        // `ActivityShareSheet` was completely broken (confirmed via a
        // mid-test screenshot showing nothing but white). Don't
        // reintroduce a loose fallback here — a real UIActivityViewController
        // failure must fail this test.
        XCTAssertTrue(
            app.otherElements["ActivityListView"].waitForExistence(timeout: 10),
            "Expected the populated share sheet (UIActivityViewController) to appear after tapping Export"
        )
    }

    /// "Select All" only acts on currently-FILTERED rows (mirrors
    /// `ReceiptList.jsx`'s header checkbox, which selects/clears all
    /// currently-LOADED rows, not the entire dataset). Scoped via a
    /// unique custom Category (picked through the Filter sheet, a Picker
    /// interaction) rather than the search field — search leaves the
    /// keyboard/search-bar in its "active" state, which hides the normal
    /// top toolbar (including selectButton) behind a Cancel affordance;
    /// the Filter sheet has no such issue since it's a modal that fully
    /// dismisses back to the normal toolbar on "Done".
    func testSelectAllSelectsAndDeselectsAllFilteredReceipts() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        let runID = String(UUID().uuidString.prefix(8))
        let category = "SelectAllCat\(runID)"
        let firstName = "SelectAllTest First \(runID)"
        let secondName = "SelectAllTest Second \(runID)"
        addReceiptWithCategory(app, merchant: firstName, totalCost: "3.00", category: category)
        addReceiptWithCategory(app, merchant: secondName, totalCost: "4.00", category: category)

        XCTAssertTrue(app.staticTexts[firstName].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[secondName].waitForExistence(timeout: 5))

        app.buttons["filterButton"].tap()
        app.buttons["categoryFilterPicker"].tap()
        app.buttons[category].tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts[firstName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[secondName].waitForExistence(timeout: 5))

        app.buttons["selectButton"].tap()

        // A plain `Button(String)`'s title IS its accessibility label
        // directly (no nested staticTexts child to query, unlike the
        // menu-style categoryPicker elsewhere) — assert on `.label`.
        let selectAllButton = app.buttons["selectAllButton"]
        XCTAssertTrue(selectAllButton.waitForExistence(timeout: 5))
        XCTAssertEqual(selectAllButton.label, "Select All")
        selectAllButton.tap()

        // "N selected" (driven by `selection.count`) is the reliable signal
        // that both rows actually got selected — SF Symbol `Image`s with an
        // `.accessibilityIdentifier` inside this row's `HStack` don't
        // reliably surface as individually queryable `app.images` elements
        // in XCUITest (queried 0 matches even with the count text correctly
        // showing "2 selected"), so don't assert on that image identifier
        // here; the count text plus the button label toggling below is
        // sufficient proof the feature works.
        XCTAssertTrue(app.staticTexts["2 selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(selectAllButton.label, "Deselect All")

        selectAllButton.tap()

        XCTAssertFalse(app.staticTexts["2 selected"].exists)
        XCTAssertEqual(selectAllButton.label, "Select All")
    }

    private func addReceiptWithCategory(_ app: XCUIApplication, merchant: String, totalCost: String, category: String) {
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

        app.buttons["categoryPicker"].tap()
        // "Custom category…" is always the LAST option in the merged
        // predefined+in-use list, so it sinks further down (needing a
        // scroll to reach) the more distinct custom categories this
        // on-device store has accumulated across repeated test runs —
        // same lazy/off-screen-content class of issue as the Slice 6
        // dashboard "By Category" section lesson. Swipe up a few times
        // if it's not immediately present before giving up.
        let customCategoryOption = app.buttons["Custom category…"]
        for _ in 0..<5 where !customCategoryOption.exists {
            app.swipeUp()
        }
        XCTAssertTrue(customCategoryOption.waitForExistence(timeout: 5))
        customCategoryOption.tap()
        let customField = app.textFields["customCategoryField"]
        XCTAssertTrue(customField.waitForExistence(timeout: 5))
        customField.tap()
        customField.typeText(category)

        app.buttons["saveReceiptButton"].tap()
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
