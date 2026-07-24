import XCTest
@testable import ReceiptTracker

final class ReceiptFilterTests: XCTestCase {
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
            Receipt(date: date(2026, 7, 19), totalCost: 34.62, merchant: "Panera Bread", itemDescription: "Bagels", category: "Travel"),
            Receipt(date: date(2026, 5, 25), totalCost: 241.64, merchant: "Lowe's", itemDescription: "Screws", category: nil),
            Receipt(date: date(2025, 12, 12), totalCost: 111.62, merchant: "Lowe's", itemDescription: "Shower head", category: "Groceries"),
            Receipt(date: date(2025, 11, 8), totalCost: 41.52, merchant: "Subway", itemDescription: "Subs", category: nil),
        ]
    }

    func testNoFiltersReturnsEverything() {
        let receipts = makeReceipts()
        let result = ReceiptFilter.apply(to: receipts, calendar: calendar)
        XCTAssertEqual(result.count, 4)
    }

    func testFilterByYear() {
        let receipts = makeReceipts()
        let result = ReceiptFilter.apply(to: receipts, year: 2026, calendar: calendar)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { calendar.component(.year, from: $0.date) == 2026 })
    }

    func testFilterByMonth() {
        let receipts = makeReceipts()
        let result = ReceiptFilter.apply(to: receipts, month: 12, calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.merchant, "Lowe's")
        XCTAssertEqual(result.first?.totalCost, 111.62)
    }

    func testFilterByYearAndMonthCombinesWithAND() {
        let receipts = makeReceipts()
        let result = ReceiptFilter.apply(to: receipts, year: 2025, month: 11, calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.merchant, "Subway")
    }

    func testFilterByCategory() {
        let receipts = makeReceipts()
        let result = ReceiptFilter.apply(to: receipts, category: "Groceries", calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.merchant, "Lowe's")
        XCTAssertEqual(result.first?.totalCost, 111.62)
    }

    func testSearchMatchesMerchantCaseInsensitively() {
        let receipts = makeReceipts()
        let result = ReceiptFilter.apply(to: receipts, searchText: "panera", calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.merchant, "Panera Bread")
    }

    func testSearchMatchesDescription() {
        let receipts = makeReceipts()
        let result = ReceiptFilter.apply(to: receipts, searchText: "screws", calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.merchant, "Lowe's")
        XCTAssertEqual(result.first?.totalCost, 241.64)
    }

    func testSearchMatchesAmount() {
        let receipts = makeReceipts()
        let result = ReceiptFilter.apply(to: receipts, searchText: "41.52", calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.merchant, "Subway")
    }

    func testAllFiltersCombineWithAND() {
        let receipts = makeReceipts()
        let result = ReceiptFilter.apply(to: receipts, year: 2025, category: "Groceries", searchText: "shower", calendar: calendar)
        XCTAssertEqual(result.count, 1)

        let noMatch = ReceiptFilter.apply(to: receipts, year: 2026, category: "Groceries", calendar: calendar)
        XCTAssertEqual(noMatch.count, 0)
    }

    func testYearOptionsReturnsLast6YearsDescending() {
        let options = ReceiptFilter.yearOptions
        XCTAssertEqual(options.count, 6)
        let currentYear = Calendar.current.component(.year, from: Date())
        XCTAssertEqual(options.first, currentYear)
        XCTAssertEqual(options.last, currentYear - 5)
    }

    func testMonthNamesHas12Entries() {
        XCTAssertEqual(ReceiptFilter.monthNames.count, 12)
        XCTAssertEqual(ReceiptFilter.monthNames.first, "January")
        XCTAssertEqual(ReceiptFilter.monthNames.last, "December")
    }
}
