import XCTest
@testable import ReceiptTracker

final class CategoryOptionsTests: XCTestCase {
    func testPredefinedHas8Categories() {
        XCTAssertEqual(CategoryOptions.predefined.count, 8)
        XCTAssertEqual(CategoryOptions.predefined.first, "Office Supplies")
        XCTAssertEqual(CategoryOptions.predefined.last, "Other")
    }

    func testMergeWithNoInUseCategoriesReturnsPredefinedOnly() {
        let merged = CategoryOptions.mergeWithInUseCategories([])
        XCTAssertEqual(merged, CategoryOptions.predefined)
    }

    func testMergeAppendsCustomCategoriesAlphabeticallyAfterPredefined() {
        let merged = CategoryOptions.mergeWithInUseCategories(["Groceries", "Client Gifts"])
        XCTAssertEqual(merged, CategoryOptions.predefined + ["Client Gifts", "Groceries"])
    }

    func testMergeDeduplicatesAgainstPredefined() {
        let merged = CategoryOptions.mergeWithInUseCategories(["Travel", "Groceries"])
        XCTAssertEqual(merged, CategoryOptions.predefined + ["Groceries"])
        XCTAssertEqual(merged.filter { $0 == "Travel" }.count, 1)
    }
}
