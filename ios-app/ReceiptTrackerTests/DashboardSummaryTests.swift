import XCTest
@testable import ReceiptTracker

final class DashboardSummaryTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeReceipts() -> [Receipt] {
        [
            Receipt(date: date(2026, 7, 19), totalCost: 34.62, merchant: "Panera", category: "Travel"),
            Receipt(date: date(2026, 7, 17), totalCost: 65.38, merchant: "Costco", category: "Groceries"),
            Receipt(date: date(2026, 5, 25), totalCost: 241.64, merchant: "Lowe's", category: nil),
            Receipt(date: date(2025, 12, 12), totalCost: 111.62, merchant: "Lowe's", category: "Groceries"),
            Receipt(date: date(2025, 11, 8), totalCost: 41.52, merchant: "Subway", category: nil),
        ]
    }

    func testYearTotalSumsOnlyThatYear() {
        let summary = DashboardSummary.compute(from: makeReceipts(), year: 2026, calendar: calendar)
        XCTAssertEqual(summary.yearTotal, 34.62 + 65.38 + 241.64, accuracy: 0.001)
    }

    func testPriorYearIsYearMinus1AndSumsCorrectly() {
        let summary = DashboardSummary.compute(from: makeReceipts(), year: 2026, calendar: calendar)
        XCTAssertEqual(summary.priorYear, 2025)
        XCTAssertEqual(summary.priorYearTotal, 111.62 + 41.52, accuracy: 0.001)
    }

    func testMonthlyTotalsHas12EntriesInOrderWithZerosForEmptyMonths() {
        let summary = DashboardSummary.compute(from: makeReceipts(), year: 2026, calendar: calendar)
        XCTAssertEqual(summary.monthlyTotals.count, 12)
        XCTAssertEqual(summary.monthlyTotals.map(\.month), Array(1...12))
        XCTAssertEqual(summary.monthlyTotals[0].total, 0) // January, empty
        XCTAssertEqual(summary.monthlyTotals[4].total, 241.64, accuracy: 0.001) // May
        XCTAssertEqual(summary.monthlyTotals[6].total, 34.62 + 65.38, accuracy: 0.001) // July, two receipts summed
    }

    func testCategoryTotalsGroupsNilAsUncategorizedAndSortsDescending() {
        let summary = DashboardSummary.compute(from: makeReceipts(), year: 2026, calendar: calendar)
        // 2026 receipts: Travel 34.62, Groceries 65.38, Uncategorized (nil) 241.64
        XCTAssertEqual(summary.categoryTotals.count, 3)
        XCTAssertEqual(summary.categoryTotals[0].category, "Uncategorized")
        XCTAssertEqual(summary.categoryTotals[0].total, 241.64, accuracy: 0.001)
        XCTAssertEqual(summary.categoryTotals[1].category, "Groceries")
        XCTAssertEqual(summary.categoryTotals[2].category, "Travel")
    }

    func testEmptyYearReturnsZeroesNotCrash() {
        let summary = DashboardSummary.compute(from: makeReceipts(), year: 2020, calendar: calendar)
        XCTAssertEqual(summary.yearTotal, 0)
        XCTAssertEqual(summary.monthlyTotals.count, 12)
        XCTAssertTrue(summary.monthlyTotals.allSatisfy { $0.total == 0 })
        XCTAssertEqual(summary.categoryTotals, [])
    }
}
