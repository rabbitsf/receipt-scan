import PDFKit
import UIKit

/// How a PDF's pages are sent for scanning: at what size and quality, and
/// in how many requests. Rule (confirmed 2026-10-18): render normally; if
/// the pages don't fit one request for the selected provider, shrink them;
/// if they still don't fit, split into consecutive parts.
/// Mirrors `frontend/src/pdfScanBudget.js`.
enum PDFScanBudget {
    struct Step: Equatable {
        let maxEdge: CGFloat
        let quality: CGFloat
    }

    /// Above this many pages Claude needs every image ≤ 2000 px, so all
    /// providers render a little smaller (one simple rule).
    static let manyPagesThreshold = 20

    /// Tried in order; the last one is the readable floor.
    static func steps(pageCount: Int) -> [Step] {
        [
            Step(maxEdge: pageCount > manyPagesThreshold ? 2000 : 2200, quality: 0.8),
            Step(maxEdge: 1600, quality: 0.7),
            Step(maxEdge: 1300, quality: 0.6),
        ]
    }

    /// Prompt, schema, labels and JSON around the images.
    static let requestOverheadBytes = 64 * 1024
    static let perImageOverheadBytes = 256
    /// Stay under each provider's limit with room to spare.
    static let safetyFactor = 0.9

    static func requestBytes(imageByteCounts: [Int]) -> Int {
        requestOverheadBytes + imageByteCounts.reduce(0) { $0 + base64Length($1) + perImageOverheadBytes }
    }

    static func fitsInOneRequest(imageByteCounts: [Int], provider: OCRProvider) -> Bool {
        imageByteCounts.count <= provider.maxImagesPerRequest
            && Double(requestBytes(imageByteCounts: imageByteCounts)) <= Double(provider.maxRequestBytes) * safetyFactor
    }

    /// Consecutive ranges of image indexes, each small enough for one request.
    static func parts(imageByteCounts: [Int], provider: OCRProvider) -> [Range<Int>] {
        var parts: [Range<Int>] = []
        var start = 0
        while start < imageByteCounts.count {
            var end = start + 1
            while end < imageByteCounts.count,
                  fitsInOneRequest(imageByteCounts: Array(imageByteCounts[start...end]), provider: provider) {
                end += 1
            }
            parts.append(start..<end)
            start = end
        }
        return parts
    }

    struct Prepared {
        /// One JPEG per scanned page, in file order.
        let images: [Data]
        /// Requests to send; a single range when everything fits at once.
        let parts: [Range<Int>]
        /// True when pages were rendered smaller than normal to fit.
        let wasShrunk: Bool
    }

    /// Renders the first `pageCount` pages of `document` for `provider`,
    /// shrinking then splitting as needed.
    static func prepare(document: PDFDocument, pageCount: Int, provider: OCRProvider) -> Prepared {
        let pages = 0..<min(pageCount, document.pageCount)
        let steps = steps(pageCount: pages.count)
        var images: [Data] = []
        for (index, step) in steps.enumerated() {
            images = PDFPageRenderer.renderJPEGs(of: document, pages: pages, maxEdge: step.maxEdge, quality: step.quality)
            if fitsInOneRequest(imageByteCounts: images.map(\.count), provider: provider) {
                return Prepared(images: images, parts: images.isEmpty ? [] : [0..<images.count], wasShrunk: index > 0)
            }
        }
        return Prepared(images: images, parts: parts(imageByteCounts: images.map(\.count), provider: provider), wasShrunk: true)
    }

    private static func base64Length(_ bytes: Int) -> Int {
        (bytes + 2) / 3 * 4
    }
}

/// Which of a PDF's pages each receipt found in it keeps (confirmed rules,
/// 2026-10-18). Page numbers are 1-based positions in the file.
/// Mirrors `frontend/src/pdfScanBudget.js`.
enum PDFPageAssignment {
    struct Result: Equatable {
        /// One entry per receipt, in the order the scan returned them.
        let pagesPerReceipt: [[Int]]
        /// Pages no receipt keeps (only possible when just the first pages were scanned).
        let unkeptPages: [Int]
    }

    /// - Parameters:
    ///   - receiptPages: the `pages` each receipt reported, already as file positions.
    ///   - scannedPageCount: how many leading pages were scanned.
    ///   - totalPageCount: pages in the file.
    static func assign(receiptPages: [[Int]], scannedPageCount: Int, totalPageCount: Int) -> Result {
        let allPages = totalPageCount > 0 ? Array(1...totalPageCount) : []
        guard receiptPages.count > 1 else {
            return Result(pagesPerReceipt: receiptPages.map { _ in allPages }, unkeptPages: [])
        }
        let perReceipt = receiptPages.map { reported -> [Int] in
            let valid = Array(Set(reported.filter { (1...max(scannedPageCount, 1)).contains($0) && $0 <= totalPageCount })).sorted()
            return valid.isEmpty ? allPages : valid
        }
        let kept = Set(perReceipt.joined())
        return Result(pagesPerReceipt: perReceipt, unkeptPages: allPages.filter { !kept.contains($0) && $0 > scannedPageCount })
    }

    /// A part's own "Image N" numbers (1-based) → file page positions.
    static func filePages(_ partPages: [Int], part: Range<Int>) -> [Int] {
        partPages.filter { (1...part.count).contains($0) }.map { part.lowerBound + $0 }
    }

    /// "pages 1–3", "page 2", "pages 1, 3, 5".
    static func label(_ pages: [Int]) -> String {
        guard let first = pages.first else { return "" }
        if pages.count == 1 { return "page \(first)" }
        if pages == Array(first...(pages.last!)) { return "pages \(first)–\(pages.last!)" }
        return "pages " + pages.map(String.init).joined(separator: ", ")
    }
}

/// The PDF a receipt keeps: just its own pages, or the original file
/// unchanged when it keeps every page.
enum PDFSubset {
    static func data(of document: PDFDocument, originalData: Data, pages: [Int]) -> Data? {
        if pages == Array(1...max(document.pageCount, 1)), document.pageCount > 0 { return originalData }
        let subset = PDFDocument()
        for (index, pageNumber) in pages.enumerated() {
            guard let page = document.page(at: pageNumber - 1)?.copy() as? PDFPage else { return nil }
            subset.insert(page, at: index)
        }
        return subset.pageCount > 0 ? subset.dataRepresentation() : nil
    }
}
