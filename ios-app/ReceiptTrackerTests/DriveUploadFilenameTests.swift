import XCTest
@testable import ReceiptTracker

final class DriveUploadFilenameTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testIncludesDateAndMerchant() {
        let name = DriveUploadFilename.make(date: date(2026, 8, 5), merchant: "Panera Bread", fallbackID: "abc123")
        XCTAssertEqual(name, "2026-08-05_Panera Bread.jpg")
    }

    func testFallsBackToIDWhenMerchantIsNil() {
        let name = DriveUploadFilename.make(date: date(2026, 8, 5), merchant: nil, fallbackID: "abc123")
        XCTAssertEqual(name, "2026-08-05_abc123.jpg")
    }

    func testFallsBackToIDWhenMerchantIsBlank() {
        let name = DriveUploadFilename.make(date: date(2026, 8, 5), merchant: "   ", fallbackID: "abc123")
        XCTAssertEqual(name, "2026-08-05_abc123.jpg")
    }

    func testStripsFilesystemUnsafeCharactersFromMerchant() {
        let name = DriveUploadFilename.make(date: date(2026, 8, 5), merchant: "A/B:C*D?E\"F<G>H|I", fallbackID: "abc123")
        XCTAssertEqual(name, "2026-08-05_A-B-C-D-E-F-G-H-I.jpg")
    }

    func testCollapsesRepeatedWhitespaceAndTrimsEdges() {
        let name = DriveUploadFilename.make(date: date(2026, 8, 5), merchant: "  Panera   Bread  ", fallbackID: "abc123")
        XCTAssertEqual(name, "2026-08-05_Panera Bread.jpg")
    }

    func testDifferentDatesProduceDifferentFilenames() {
        let a = DriveUploadFilename.make(date: date(2026, 8, 5), merchant: "Costco", fallbackID: "x")
        let b = DriveUploadFilename.make(date: date(2026, 8, 6), merchant: "Costco", fallbackID: "x")
        XCTAssertNotEqual(a, b)
    }
}
