import Foundation

/// CSV export, standing in for the web app's PDF/Excel export
/// (`backend/src/services/exportService.js`) — this standalone app has no
/// backend to run `pdfkit`/`exceljs` on, so CSV (needs no library, shares
/// via the system share sheet like any file) covers the same need for now.
/// Same 6 columns as the web export plus one iOS-only addition: Date,
/// Merchant, Total, Description, Category, Group, Note. `Group` has no web
/// app equivalent (see `GroupOptions`) — empty (not "Ungrouped") for
/// receipts with no group, since most receipts are expected to have none.
enum ReceiptCSVExporter {
    static func csv(for receipts: [Receipt]) -> String {
        var lines = ["Date,Merchant,Total,Description,Category,Group,Note"]
        for receipt in receipts {
            let fields = [
                DateOnly.string(from: receipt.date),
                receipt.merchant ?? "",
                String(format: "%.2f", receipt.totalCost),
                receipt.itemDescription ?? "",
                receipt.category ?? "Uncategorized",
                receipt.group ?? "",
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
