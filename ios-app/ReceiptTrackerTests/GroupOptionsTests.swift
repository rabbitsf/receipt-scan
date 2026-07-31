import XCTest
@testable import ReceiptTracker

final class GroupOptionsTests: XCTestCase {
    func testAvailableGroupsWithNoReceiptsOrCustomGroupsIsEmpty() {
        XCTAssertEqual(GroupOptions.availableGroups(from: []), [])
    }

    func testAvailableGroupsIncludesInUseGroupsSortedAndDeduplicated() {
        let receipts = [
            Receipt(date: Date(), totalCost: 1, group: "Trip B"),
            Receipt(date: Date(), totalCost: 2, group: "Trip A"),
            Receipt(date: Date(), totalCost: 3, group: "Trip A"),
            Receipt(date: Date(), totalCost: 4, group: nil),
        ]
        XCTAssertEqual(GroupOptions.availableGroups(from: receipts), ["Trip A", "Trip B"])
    }

    func testAvailableGroupsIncludesCustomGroupsEvenWithoutInUseReceipts() {
        let merged = GroupOptions.availableGroups(from: [], customGroups: ["Conference"])
        XCTAssertEqual(merged, ["Conference"])
    }

    func testAvailableGroupsDeduplicatesCustomGroupsAgainstInUse() {
        let receipts = [Receipt(date: Date(), totalCost: 1, group: "Conference")]
        let merged = GroupOptions.availableGroups(from: receipts, customGroups: ["Conference", "Offsite"])
        XCTAssertEqual(merged, ["Conference", "Offsite"])
    }

    func testUsageCountCountsOnlyMatchingReceipts() {
        let receipts = [
            Receipt(date: Date(), totalCost: 1, group: "Trip A"),
            Receipt(date: Date(), totalCost: 2, group: "Trip A"),
            Receipt(date: Date(), totalCost: 3, group: "Trip B"),
            Receipt(date: Date(), totalCost: 4, group: nil),
        ]
        XCTAssertEqual(GroupOptions.usageCount(of: "Trip A", in: receipts), 2)
        XCTAssertEqual(GroupOptions.usageCount(of: "Trip B", in: receipts), 1)
        XCTAssertEqual(GroupOptions.usageCount(of: "Unused", in: receipts), 0)
    }

    func testRenameInUseUpdatesOnlyMatchingReceipts() {
        let matching = Receipt(date: Date(), totalCost: 1, group: "Trip A")
        let other = Receipt(date: Date(), totalCost: 2, group: "Trip B")
        GroupOptions.renameInUse(from: "Trip A", to: "Business Trip", in: [matching, other])
        XCTAssertEqual(matching.group, "Business Trip")
        XCTAssertEqual(other.group, "Trip B")
    }
}
