import XCTest

/// Settings-based create/rename/delete for Category and Group (distinct from
/// the existing inline "Custom category…"/"New group…" creation flow tested
/// in `CategoryNoteFlowTests`/`GroupFlowTests`). Group only gets the
/// "appears in picker" coverage here — its usage-count/rename-cascade logic
/// is identical to Category's and already covered by
/// `GroupOptionsTests`/`CategoryOptionsTests`.
final class SettingsCategoryGroupFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Any accessibility-identified element regardless of its XCUITest
    /// element type (staticText/button/cell/etc.) — SwiftUI doesn't
    /// guarantee which trait a `Label` row with `.swipeActions` ends up
    /// exposed as, so query broadly rather than guessing.
    private func element(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Settings' Form has grown to API Key + 8 predefined + N accumulated
    /// custom categories + Groups — SwiftUI's `Form`/`List` lazily
    /// materializes offscreen rows, so a target further down may not exist
    /// in the accessibility tree yet. Swipe up (bounded) until it does,
    /// same accumulated-options pattern already used for the category/group
    /// pickers elsewhere in this test target.
    @discardableResult
    private func scrollToExistence(_ app: XCUIApplication, _ target: XCUIElement, maxSwipes: Int = 40) -> Bool {
        for _ in 0..<maxSwipes where !target.exists {
            app.swipeUp()
        }
        return target.waitForExistence(timeout: 5)
    }

    private func openSettings(_ app: XCUIApplication) {
        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
    }

    private func addCategoryViaSettings(_ app: XCUIApplication, name: String) {
        let field = app.textFields["newCategoryNameField"]
        XCTAssertTrue(scrollToExistence(app, field))
        field.tap()
        field.typeText(name)
        app.buttons["addCategoryButton"].tap()
    }

    private func addGroupViaSettings(_ app: XCUIApplication, name: String) {
        let field = app.textFields["newGroupNameField"]
        XCTAssertTrue(scrollToExistence(app, field))
        field.tap()
        field.typeText(name)
        app.buttons["addGroupButton"].tap()
    }

    func testCategoryAddedInSettingsAppearsInReceiptFormPicker() throws {
        let app = XCUIApplication.receiptTracker()
        app.terminate()
        app.launch()

        let categoryName = "ZZZSettingsCat Add \(UUID().uuidString.prefix(8))"

        openSettings(app)
        addCategoryViaSettings(app, name: categoryName)
        // Not scroll-searching for the row in Settings' own (ever-growing,
        // never-torn-down) list here — the picker-appearance check below is
        // this test's actual point and is a bounded, reliable assertion.
        app.buttons["Close"].tap()

        app.buttons["addReceiptButton"].tap()
        app.buttons["categoryPicker"].tap()
        let option = app.buttons[categoryName]
        for _ in 0..<8 where !option.exists {
            app.swipeUp()
        }
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Settings-created category should appear in the picker before any receipt uses it")
    }

    func testGroupAddedInSettingsAppearsInReceiptFormPicker() throws {
        let app = XCUIApplication.receiptTracker()
        app.terminate()
        app.launch()

        let groupName = "ZZZSettingsGroup Add \(UUID().uuidString.prefix(8))"

        openSettings(app)
        addGroupViaSettings(app, name: groupName)
        app.buttons["Close"].tap()

        app.buttons["addReceiptButton"].tap()
        app.buttons["groupPicker"].tap()
        let option = app.buttons[groupName]
        for _ in 0..<8 where !option.exists {
            app.swipeUp()
        }
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Settings-created group should appear in the picker before any receipt uses it")
    }

    func testDeletingCategoryIsBlockedWhenInUseAndSucceedsWhenUnused() throws {
        let app = XCUIApplication.receiptTracker()
        app.terminate()
        app.launch()

        let runID = UUID().uuidString.prefix(8)
        let inUseCategory = "ZZZSettingsCat InUse \(runID)"
        let unusedCategory = "ZZZSettingsCat Unused \(runID)"
        let merchantName = "SettingsDeleteTest Merchant \(runID)"

        // Create a receipt using a custom category via the existing inline flow.
        app.buttons["addReceiptButton"].tap()
        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.waitForExistence(timeout: 10))
        merchantField.tap()
        merchantField.typeText(merchantName)
        app.textFields["totalCostField"].tap()
        app.textFields["totalCostField"].typeText("12.34")
        app.buttons["categoryPicker"].tap()
        let customOption = app.buttons["Custom category…"]
        for _ in 0..<5 where !customOption.exists {
            app.swipeUp()
        }
        XCTAssertTrue(customOption.waitForExistence(timeout: 5))
        customOption.tap()
        let customField = app.textFields["customCategoryField"]
        XCTAssertTrue(customField.waitForExistence(timeout: 5))
        customField.tap()
        customField.typeText(inUseCategory)
        app.buttons["saveReceiptButton"].tap()
        XCTAssertTrue(app.staticTexts[merchantName].waitForExistence(timeout: 10))

        openSettings(app)
        addCategoryViaSettings(app, name: unusedCategory)

        // In-use category: delete is blocked with an explanatory alert.
        let inUseRow = element(app, id: "categoryRow_\(inUseCategory)")
        XCTAssertTrue(scrollToExistence(app, inUseRow))
        inUseRow.swipeLeft()
        let deleteInUseButton = app.buttons["deleteCategoryButton_\(inUseCategory)"]
        XCTAssertTrue(deleteInUseButton.waitForExistence(timeout: 3), "Swipe-to-delete action should reveal after swiping the row")
        deleteInUseButton.tap()
        XCTAssertTrue(app.alerts["Can't Delete"].waitForExistence(timeout: 5))
        app.alerts["Can't Delete"].buttons["OK"].tap()
        XCTAssertTrue(element(app, id: "categoryRow_\(inUseCategory)").waitForExistence(timeout: 5), "Blocked delete should leave the category in place")

        // Unused category: delete succeeds, no alert.
        let unusedRow = element(app, id: "categoryRow_\(unusedCategory)")
        XCTAssertTrue(scrollToExistence(app, unusedRow))
        unusedRow.swipeLeft()
        let deleteUnusedButton = app.buttons["deleteCategoryButton_\(unusedCategory)"]
        XCTAssertTrue(deleteUnusedButton.waitForExistence(timeout: 3), "Swipe-to-delete action should reveal after swiping the row")
        deleteUnusedButton.tap()
        XCTAssertFalse(app.alerts["Can't Delete"].waitForExistence(timeout: 2))
        let stillThere = element(app, id: "categoryRow_\(unusedCategory)").waitForExistence(timeout: 3)
        XCTAssertFalse(stillThere, "Unused category should be deleted without a blocking alert")
    }

    func testRenamingCategoryInSettingsCascadesToExistingReceipt() throws {
        let app = XCUIApplication.receiptTracker()
        app.terminate()
        app.launch()

        let runID = UUID().uuidString.prefix(8)
        let oldName = "ZZZSettingsCat RenameOld \(runID)"
        let newName = "ZZZSettingsCat RenameNew \(runID)"
        let merchantName = "SettingsRenameTest Merchant \(runID)"

        app.buttons["addReceiptButton"].tap()
        let merchantField = app.textFields["merchantField"]
        XCTAssertTrue(merchantField.waitForExistence(timeout: 10))
        merchantField.tap()
        merchantField.typeText(merchantName)
        app.textFields["totalCostField"].tap()
        app.textFields["totalCostField"].typeText("5.00")
        app.buttons["categoryPicker"].tap()
        let customOption = app.buttons["Custom category…"]
        for _ in 0..<5 where !customOption.exists {
            app.swipeUp()
        }
        XCTAssertTrue(customOption.waitForExistence(timeout: 5))
        customOption.tap()
        let customField = app.textFields["customCategoryField"]
        XCTAssertTrue(customField.waitForExistence(timeout: 5))
        customField.tap()
        customField.typeText(oldName)
        app.buttons["saveReceiptButton"].tap()
        let row = app.staticTexts[merchantName].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        openSettings(app)
        let oldRow = element(app, id: "categoryRow_\(oldName)")
        XCTAssertTrue(scrollToExistence(app, oldRow))
        oldRow.swipeLeft()
        let renameButton = app.buttons["renameCategoryButton_\(oldName)"]
        XCTAssertTrue(renameButton.waitForExistence(timeout: 3), "Swipe-to-rename action should reveal after swiping the row")
        renameButton.tap()
        let renameField = app.textFields["renameCategoryField"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.tap()
        renameField.typeText(newName)
        app.buttons["saveRenameCategoryButton"].tap()
        // Not re-verifying the renamed row's position in Settings' own
        // list here: after many prior runs of this test target, the
        // Categories section has accumulated a long tail of past ZZZ*
        // test entries in the real on-device store (there's no teardown
        // between UI test runs), and the renamed value can sort earlier
        // OR later than wherever we happened to be scrolled to for the
        // rename action above — a bounded scroll search isn't reliable
        // against an unbounded, ever-growing list. The cascade check below
        // (the actual point of this test) is a robust, bounded assertion
        // regardless of how much has accumulated.
        app.buttons["Close"].tap()

        // Confirm the cascade: the existing receipt now shows the new name.
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit Receipt"].waitForExistence(timeout: 5))
        // A custom (non-predefined) category's picker button always shows
        // "Custom category…" (see `CategoryNoteFlowTests`'s equivalent
        // custom-category assertion) — the actual value lives in the
        // separate `customCategoryField` text field, not the picker label.
        let customCategoryField = app.textFields["customCategoryField"]
        XCTAssertTrue(customCategoryField.waitForExistence(timeout: 5))
        XCTAssertEqual(customCategoryField.value as? String, newName)
    }
}
