import XCTest
@testable import ReceiptTracker

final class ReceiptFormViewTests: XCTestCase {
    /// Regression test for a real bug: OCR-extracted dates ("YYYY-MM-DD")
    /// used to be parsed as UTC midnight, then handed to `DatePicker`/list
    /// display (both render in the LOCAL time zone) — silently shifting
    /// the displayed date back by a day for anyone west of UTC (reported:
    /// scanned receipt dates showing one day behind). Asserting via
    /// `Calendar.current` (whatever time zone the machine running this
    /// test happens to be in) directly checks the invariant that broke:
    /// the parsed date's LOCAL calendar day must match the input string,
    /// not its UTC calendar day.
    func testParseOCRDateReturnsTheCorrectLocalCalendarDay() throws {
        let parsed = try XCTUnwrap(ReceiptFormView.parseOCRDate("2026-07-23"))

        let components = Calendar.current.dateComponents([.year, .month, .day], from: parsed)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 23)
    }

    func testParseOCRDateReturnsNilForMalformedString() {
        XCTAssertNil(ReceiptFormView.parseOCRDate("not a date"))
        XCTAssertNil(ReceiptFormView.parseOCRDate(""))
    }
}
