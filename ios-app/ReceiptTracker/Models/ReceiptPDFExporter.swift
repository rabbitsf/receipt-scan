import UIKit

/// PDF export for Web Access over Wi-Fi — the Swift version of the Mac
/// backend's `generateReceiptsPdf` (`backend/src/services/exportService.js`):
/// A4, title, "N receipts — Total: $X" line, then one row per receipt with
/// the same 7 columns as the CSV export.
enum ReceiptPDFExporter {
    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 40
    private static let rowHeight: CGFloat = 16

    /// Column titles and relative widths (sum = 1).
    private static let columns: [(title: String, width: CGFloat)] = [
        ("Date", 0.12), ("Merchant", 0.17), ("Total", 0.10), ("Description", 0.21),
        ("Category", 0.14), ("Group", 0.12), ("Note", 0.14),
    ]

    static func pdf(for receipts: [Receipt]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let contentWidth = pageSize.width - margin * 2
        let total = receipts.reduce(0) { $0 + $1.totalCost }

        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let bodyFont = UIFont.systemFont(ofSize: 11)
        let headerFont = UIFont.boldSystemFont(ofSize: 8.5)
        let cellFont = UIFont.systemFont(ofSize: 8.5)

        return renderer.pdfData { context in
            var y: CGFloat = 0

            func drawHeaderRow() {
                drawRow(columns.map(\.title), font: headerFont, y: y, contentWidth: contentWidth)
                y += rowHeight
                let line = UIBezierPath()
                line.move(to: CGPoint(x: margin, y: y - 3))
                line.addLine(to: CGPoint(x: pageSize.width - margin, y: y - 3))
                UIColor.gray.setStroke()
                line.lineWidth = 0.5
                line.stroke()
            }

            context.beginPage()
            y = margin
            ("Receipts" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont])
            y += 28
            let countText = "\(receipts.count) receipt\(receipts.count == 1 ? "" : "s") — Total: \(String(format: "$%.2f", total))"
            (countText as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont])
            y += 26
            drawHeaderRow()

            for receipt in receipts {
                if y + rowHeight > pageSize.height - margin {
                    context.beginPage()
                    y = margin
                    drawHeaderRow()
                }
                drawRow([
                    DateOnly.string(from: receipt.date),
                    receipt.merchant ?? "",
                    String(format: "$%.2f", receipt.totalCost),
                    receipt.itemDescription ?? "",
                    receipt.category?.isEmpty == false ? receipt.category! : "Uncategorized",
                    receipt.group ?? "",
                    receipt.note ?? "",
                ], font: cellFont, y: y, contentWidth: contentWidth)
                y += rowHeight
            }
        }
    }

    private static func drawRow(_ values: [String], font: UIFont, y: CGFloat, contentWidth: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        var x = margin
        for (value, column) in zip(values, columns) {
            let width = contentWidth * column.width
            let singleLine = value.replacingOccurrences(of: "\n", with: " ")
            (singleLine as NSString).draw(in: CGRect(x: x, y: y, width: width - 6, height: rowHeight), withAttributes: attributes)
            x += width
        }
    }
}
