import Foundation

/// THE "YYYY-MM-DD" date-only format used everywhere a receipt date becomes
/// text or comes back from text: OCR results, CSV export, Drive filenames
/// and the Web Access API.
///
/// Local time zone, never UTC: `receipt.date` is a local wall-clock calendar
/// day (from `DatePicker` and OCR parsing). Formatting or parsing it in UTC
/// shifts it by a day for users on the other side of UTC (see the
/// 2026-07-27 OCR/CSV date bugfix).
enum DateOnly {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
