import Foundation

/// CSV export, standing in for the web app's PDF/Excel export
/// (`backend/src/services/exportService.js`) — this standalone app has no
/// backend to run `pdfkit`/`exceljs` on, so CSV (needs no library, shares
/// via the system share sheet like any file) covers the same need for now.
/// Same 6 columns as the web export: Date, Merchant, Total, Description,
/// Category, Note.
enum ReceiptCSVExporter {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func csv(for receipts: [Receipt]) -> String {
        var lines = ["Date,Merchant,Total,Description,Category,Note"]
        for receipt in receipts {
            let fields = [
                dateFormatter.string(from: receipt.date),
                receipt.merchant ?? "",
                String(format: "%.2f", receipt.totalCost),
                receipt.itemDescription ?? "",
                receipt.category ?? "Uncategorized",
                receipt.note ?? "",
            ]
            lines.append(fields.map(escapeCSVField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    /// Wraps a field in quotes (doubling any internal quotes) if it
    /// contains a comma, quote, or newline — standard CSV escaping (RFC 4180).
    private static func escapeCSVField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
