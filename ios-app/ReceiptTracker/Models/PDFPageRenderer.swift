import PDFKit
import UIKit

/// Renders PDF pages to JPEG images so they can flow through the same OCR
/// pipeline as a camera/library photo (the provider clients only send
/// images). How many pages, and at what size/quality, is decided by
/// `PDFScanBudget`; this file only draws.
enum PDFPageRenderer {
    /// The "Scan first N pages" choice in the PDF cost popup.
    static let quickScanPages = 5

    /// Pixel size each page renders to with its long edge at `maxEdge`
    /// (page rotation included) — used for cost estimates before rendering.
    static func renderedSizes(of document: PDFDocument, pages: Range<Int>, maxEdge: CGFloat) -> [(width: Int, height: Int)] {
        pages.compactMap { index in
            guard let page = document.page(at: index), let size = targetSize(of: page, maxEdge: maxEdge) else { return nil }
            return (Int(size.width.rounded()), Int(size.height.rounded()))
        }
    }

    /// JPEGs for `pages` (0-based), long edge `maxEdge`, at scale 1 so the
    /// pixel size is exact on every device. A page that can't be drawn is
    /// skipped.
    static func renderJPEGs(of document: PDFDocument, pages: Range<Int>, maxEdge: CGFloat, quality: CGFloat) -> [Data] {
        pages.compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            return render(page: page, maxEdge: maxEdge)?.jpegData(compressionQuality: quality)
        }
    }

    static func render(page: PDFPage, maxEdge: CGFloat) -> UIImage? {
        guard let size = targetSize(of: page, maxEdge: maxEdge) else { return nil }
        // `thumbnail(of:for:)` handles rotation and coordinate flipping; it
        // may come back at screen scale, so redraw at scale 1.
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            thumbnail.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func targetSize(of page: PDFPage, maxEdge: CGFloat) -> CGSize? {
        var size = page.bounds(for: .mediaBox).size
        guard size.width > 0, size.height > 0 else { return nil }
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        let scale = maxEdge / max(size.width, size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}
