import XCTest
import SwiftData
@testable import ReceiptTracker

@MainActor
final class CustomValueStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: Receipt.self, CustomCategory.self, CustomGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testAddTrimsAndListsNewCategory() {
        XCTAssertEqual(CustomValueStore.add("  Groceries ", kind: .category, in: context), "Groceries")
        XCTAssertEqual(CustomValueStore.listedNames(.category, in: context), ["Groceries"])
    }

    func testAddRejectsBlankAndPredefinedCategory() {
        XCTAssertNil(CustomValueStore.add("   ", kind: .category, in: context))
        XCTAssertNil(CustomValueStore.add("Travel", kind: .category, in: context))
        XCTAssertEqual(CustomValueStore.listedNames(.category, in: context), [])
    }

    func testAddingExistingNameDoesNotDuplicate() {
        CustomValueStore.add("Trip", kind: .group, in: context)
        XCTAssertEqual(CustomValueStore.add("Trip", kind: .group, in: context), "Trip")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CustomGroup>()).count, 1)
    }

    func testRenameCascadesToReceiptsAndKeepsNameListed() {
        let receipt = Receipt(date: Date(), totalCost: 5, category: "Snacks", group: "NY Trip")
        context.insert(receipt)
        XCTAssertEqual(CustomValueStore.rename("Snacks", to: "Food", kind: .category, in: context), "Food")
        XCTAssertEqual(CustomValueStore.rename("NY Trip", to: "Boston Trip", kind: .group, in: context), "Boston Trip")
        XCTAssertEqual(receipt.category, "Food")
        XCTAssertEqual(receipt.group, "Boston Trip")

        context.delete(receipt)
        XCTAssertEqual(CustomValueStore.listedNames(.category, in: context), ["Food"])
        XCTAssertEqual(CustomValueStore.listedNames(.group, in: context), ["Boston Trip"])
    }

    func testRenameRejectsPredefinedAndUnchangedNames() {
        CustomValueStore.add("Snacks", kind: .category, in: context)
        XCTAssertNil(CustomValueStore.rename("Snacks", to: "Travel", kind: .category, in: context))
        XCTAssertNil(CustomValueStore.rename("Travel", to: "Trips", kind: .category, in: context))
        XCTAssertNil(CustomValueStore.rename("Snacks", to: " Snacks ", kind: .category, in: context))
    }

    func testDeleteIsBlockedWhileInUse() {
        context.insert(Receipt(date: Date(), totalCost: 5, group: "Trip"))
        context.insert(Receipt(date: Date(), totalCost: 6, group: "Trip"))
        XCTAssertEqual(CustomValueStore.delete("Trip", kind: .group, in: context), .blocked(usageCount: 2))
    }

    func testDeleteRemovesUnusedCustomValue() {
        CustomValueStore.add("Snacks", kind: .category, in: context)
        XCTAssertEqual(CustomValueStore.delete("Snacks", kind: .category, in: context), .deleted)
        XCTAssertEqual(CustomValueStore.listedNames(.category, in: context), [])
    }
}
