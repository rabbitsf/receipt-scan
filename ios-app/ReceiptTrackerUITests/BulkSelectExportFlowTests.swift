import XCTest

final class BulkSelectExportFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Add two receipts, enter select mode, select one, bulk-delete it,
    /// confirm only that one is gone and the other survives.
    func testBulkSelectAndDeleteRemovesOnlySelectedReceipt() throws {
        let app = XCUIApplication.receiptTracker()
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
        let app = XCUIApplication.receiptTracker()
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

    /// In select mode the top-bar Export exports the selection, not the
    /// whole list (user-reported bug), so it's disabled until something
    /// is selected. The rule itself is unit-tested in
    /// `ReceiptListExportTests`.
    func testTopExportFollowsSelectionInSelectMode() throws {
        let app = XCUIApplication.receiptTracker()
        app.terminate()
        app.launch()

        let merchant = "TopExportTest Merchant \(UUID().uuidString.prefix(8))"
        addReceipt(app, merchant: merchant, totalCost: "6.00")
        XCTAssertTrue(app.staticTexts[merchant].waitForExistence(timeout: 10))

        let exportButton = app.buttons["exportButton"]
        XCTAssertTrue(exportButton.isEnabled)

        app.buttons["selectButton"].tap()
        XCTAssertFalse(exportButton.isEnabled, "Nothing selected yet, so nothing to export")

        app.staticTexts[merchant].firstMatch.tap()
        XCTAssertTrue(exportButton.isEnabled)
        exportButton.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10))
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
        let app = XCUIApplication.receiptTracker()
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
        selectCategoryFilter(app, category: category)
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

        // The selection count shows in the navigation title ("N Selected"),
        // not as a bottom-bar Text — that spot proved fragile twice
        // (squeezed to zero width with longer button labels, then vanished
        // again for odd counts of 3+ even after that fix — see
        // ReceiptListView.swift's comment on this). SF Symbol `Image`s with
        // an `.accessibilityIdentifier` inside this row's `HStack` don't
        // reliably surface as individually queryable `app.images` elements
        // in XCUITest either, so don't assert on that image identifier
        // here; the nav title plus the button label toggling below is
        // sufficient proof the feature works.
        XCTAssertTrue(app.navigationBars["2 Selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(selectAllButton.label, "Deselect All")

        selectAllButton.tap()

        XCTAssertFalse(app.navigationBars["2 Selected"].exists)
        XCTAssertTrue(app.navigationBars["Receipt Tracker"].waitForExistence(timeout: 5))
        XCTAssertEqual(selectAllButton.label, "Select All")
    }

    /// Regression test for a real bug: the bottom-bar selection count used
    /// to disappear specifically for odd counts of 3+ (reported by the
    /// user: showed for 1/2/4/6, silently missing for 3/5) while tapping
    /// rows one at a time. Selects three individual rows via direct taps
    /// (not Select All, matching the user's actual workflow) and confirms
    /// "3 Selected" shows as the navigation title — the count's new home
    /// after being moved out of the crowded bottom-bar HStack entirely.
    func testSelectingThreeReceiptsShowsCorrectCount() throws {
        let app = XCUIApplication.receiptTracker()
        app.terminate()
        app.launch()

        let runID = String(UUID().uuidString.prefix(8))
        let category = "OddCountCat\(runID)"
        let names = (1...3).map { "OddCountTest \($0) \(runID)" }
        for (index, name) in names.enumerated() {
            addReceiptWithCategory(app, merchant: name, totalCost: "\(index + 1).00", category: category)
        }

        for name in names {
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
        }

        app.buttons["filterButton"].tap()
        selectCategoryFilter(app, category: category)
        app.buttons["Done"].tap()

        for name in names {
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        }

        app.buttons["selectButton"].tap()
        for name in names {
            app.staticTexts[name].firstMatch.tap()
        }

        XCTAssertTrue(app.navigationBars["3 Selected"].waitForExistence(timeout: 5))
    }

    /// Same fragility class as "Custom category…" in the add-form's
    /// `categoryPicker` (see its comment below): this session's on-device
    /// store has accumulated many custom categories across repeated test
    /// runs, which can push a specific category out of immediate reach in
    /// `categoryFilterPicker`'s popup menu too — swipe up a few times
    /// before giving up. Previously unpatched here (only the add-form
    /// picker had this fix), which caused this exact failure in a full
    /// 56-test suite run once enough categories had accumulated.
    private func selectCategoryFilter(_ app: XCUIApplication, category: String) {
        app.buttons["categoryFilterPicker"].tap()
        let categoryOption = app.buttons[category]
        for _ in 0..<5 where !categoryOption.exists {
            app.swipeUp()
        }
        XCTAssertTrue(categoryOption.waitForExistence(timeout: 5))
        categoryOption.tap()
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
