import XCTest
@testable import ReceiptTracker

/// Which receipts the list's Export buttons put in the CSV. Both the
/// top-bar share icon and the select-mode Export use this rule, so a
/// selection is never silently widened to the whole list.
final class ReceiptListExportTests: XCTestCase {
    private let visible = ["a", "b", "c", "d"]

    func testOutsideSelectModeExportsEveryVisibleReceipt() {
        XCTAssertEqual(ReceiptListView.receiptsToExport(visible, isSelecting: false, selection: ["b"], id: { $0 }), visible)
    }

    func testInSelectModeExportsOnlySelectedReceiptsInListOrder() {
        XCTAssertEqual(ReceiptListView.receiptsToExport(visible, isSelecting: true, selection: ["d", "b"], id: { $0 }), ["b", "d"])
    }

    func testInSelectModeWithNothingSelectedExportsNothing() {
        XCTAssertEqual(ReceiptListView.receiptsToExport(visible, isSelecting: true, selection: [], id: { $0 }), [])
    }

    /// A receipt selected and then hidden by a filter isn't exported.
    func testSelectedReceiptHiddenByFilterIsNotExported() {
        XCTAssertEqual(ReceiptListView.receiptsToExport(["a", "b"], isSelecting: true, selection: ["b", "z"], id: { $0 }), ["b"])
    }
}
