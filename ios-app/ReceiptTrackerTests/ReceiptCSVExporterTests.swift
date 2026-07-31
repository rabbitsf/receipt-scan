import XCTest
@testable import ReceiptTracker

final class ReceiptCSVExporterTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        // Local time zone, not UTC — matches `ReceiptCSVExporter.dateFormatter`
        // now that it formats in local time (fixing a real bug: it used to
        // format in UTC while every other date in the app was already
        // local, silently shifting exported dates for users east of UTC).
        // Constructing test dates with the SAME time zone the exporter now
        // uses keeps this test deterministic regardless of which time zone
        // the machine running it is actually in.
        calendar.timeZone = TimeZone.current
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testEmptyReceiptsProducesHeaderOnly() {
        let csv = ReceiptCSVExporter.csv(for: [])
        XCTAssertEqual(csv, "Date,Merchant,Total,Description,Category,Group,Note")
    }

    func testSingleReceiptProducesCorrectRow() {
        let receipt = Receipt(
            date: date(2026, 7, 23),
            totalCost: 34.62,
            merchant: "Panera Bread",
            itemDescription: "Bagels",
            category: "Travel",
            group: "Business Trip to NY",
            note: "Reimbursable"
        )
        let csv = ReceiptCSVExporter.csv(for: [receipt])
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1], "2026-07-23,Panera Bread,34.62,Bagels,Travel,Business Trip to NY,Reimbursable")
    }

    func testNilCategoryFallsBackToUncategorized() {
        let receipt = Receipt(date: date(2026, 1, 1), totalCost: 1.00, merchant: "X")
        let csv = ReceiptCSVExporter.csv(for: [receipt])
        XCTAssertTrue(csv.contains("Uncategorized"))
    }

    func testNilMerchantDescriptionNoteBecomeEmptyFieldsNotCrash() {
        let receipt = Receipt(date: date(2026, 1, 1), totalCost: 1.00)
        let csv = ReceiptCSVExporter.csv(for: [receipt])
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[1], "2026-01-01,,1.00,,Uncategorized,,")
    }

    func testFieldContainingCommaGetsQuoted() {
        let receipt = Receipt(date: date(2026, 1, 1), totalCost: 1.00, merchant: "Smith, Jones & Co")
        let csv = ReceiptCSVExporter.csv(for: [receipt])
        XCTAssertTrue(csv.contains("\"Smith, Jones & Co\""))
    }

    func testFieldContainingQuoteGetsEscapedByDoubling() {
        let receipt = Receipt(date: date(2026, 1, 1), totalCost: 1.00, merchant: #"The "Best" Diner"#)
        let csv = ReceiptCSVExporter.csv(for: [receipt])
        XCTAssertTrue(csv.contains(#""The ""Best"" Diner""#))
    }

    func testFieldContainingNewlineGetsQuoted() {
        let receipt = Receipt(date: date(2026, 1, 1), totalCost: 1.00, itemDescription: "Line one\nLine two")
        let csv = ReceiptCSVExporter.csv(for: [receipt])
        XCTAssertTrue(csv.contains("\"Line one\nLine two\""))
    }

    func testMultipleReceiptsProduceOneRowEach() {
        let receipts = [
            Receipt(date: date(2026, 1, 1), totalCost: 1.00, merchant: "A"),
            Receipt(date: date(2026, 1, 2), totalCost: 2.00, merchant: "B"),
        ]
        let csv = ReceiptCSVExporter.csv(for: receipts)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 3) // header + 2 rows
    }
}
