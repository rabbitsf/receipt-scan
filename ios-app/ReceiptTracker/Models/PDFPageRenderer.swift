import PDFKit
import UIKit

/// Renders a PDF's pages to `UIImage`s so they can flow through the same
/// OCR pipeline as a camera/library photo — `AnthropicVisionClient` only
/// supports `"image"` content blocks (no PDF/document block type), so PDF
/// bytes can never be sent directly; this is the only way to get a
/// PDF-derived receipt through that client without modifying it.
enum PDFPageRenderer {
    /// Every page is sent to the model together so it can reason across
    /// all of them for one receipt spanning multiple pages, or decide
    /// they're actually separate receipts (see `AnthropicVisionClient`'s
    /// doc comment) — capped so an unusually long PDF can't blow up
    /// request cost/latency. Referenced by the warning alert shown before
    /// scanning, so this is the single source of truth for that number.
    static let maxPages = 5

    static func renderPages(of url: URL) -> [UIImage] {
        guard let document = PDFDocument(url: url) else {
            return []
        }
        let pageCount = min(document.pageCount, maxPages)
        guard pageCount > 0 else {
            return []
        }
        return (0..<pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            return render(page: page)
        }
    }

    private static func render(page: PDFPage) -> UIImage? {
        let pageSize = page.bounds(for: .mediaBox).size
        guard pageSize.width > 0, pageSize.height > 0 else {
            return nil
        }
        // Caps the longest edge at 2200px — good enough for OCR without
        // producing an oversized upload, same spirit as the
        // `jpegData(compressionQuality: 0.8)` already used for
        // camera/library photos elsewhere in this form.
        let maxDimension: CGFloat = 2200
        let scale = maxDimension / max(pageSize.width, pageSize.height)
        let targetSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        // `PDFPage.thumbnail(of:for:)` handles orientation/coordinate
        // flipping internally — simpler and less error-prone than manual
        // `CGContext` PDF page drawing.
        return page.thumbnail(of: targetSize, for: .mediaBox)
    }
}
