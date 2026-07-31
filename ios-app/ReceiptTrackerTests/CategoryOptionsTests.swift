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

    func testMergeIncludesCustomCategoriesEvenWithoutInUseReceipts() {
        let merged = CategoryOptions.mergeWithInUseCategories([], customCategories: ["Client Gifts"])
        XCTAssertEqual(merged, CategoryOptions.predefined + ["Client Gifts"])
    }

    func testMergeDeduplicatesCustomCategoriesAgainstInUseAndPredefined() {
        let merged = CategoryOptions.mergeWithInUseCategories(["Groceries"], customCategories: ["Groceries", "Travel"])
        XCTAssertEqual(merged, CategoryOptions.predefined + ["Groceries"])
    }

    func testUsageCountCountsOnlyMatchingReceipts() {
        let receipts = [
            Receipt(date: Date(), totalCost: 1, category: "Travel"),
            Receipt(date: Date(), totalCost: 2, category: "Travel"),
            Receipt(date: Date(), totalCost: 3, category: "Other"),
            Receipt(date: Date(), totalCost: 4, category: nil),
        ]
        XCTAssertEqual(CategoryOptions.usageCount(of: "Travel", in: receipts), 2)
        XCTAssertEqual(CategoryOptions.usageCount(of: "Other", in: receipts), 1)
        XCTAssertEqual(CategoryOptions.usageCount(of: "Unused", in: receipts), 0)
    }

    func testRenameInUseUpdatesOnlyMatchingReceipts() {
        let matching = Receipt(date: Date(), totalCost: 1, category: "Groceries")
        let other = Receipt(date: Date(), totalCost: 2, category: "Travel")
        CategoryOptions.renameInUse(from: "Groceries", to: "Food", in: [matching, other])
        XCTAssertEqual(matching.category, "Food")
        XCTAssertEqual(other.category, "Travel")
    }
}
