import XCTest
@testable import ReceiptTracker

final class PDFPageRendererTests: XCTestCase {
    /// Synthesizes a small PDF in-memory via `UIGraphicsPDFRenderer` rather
    /// than committing a binary fixture file — consistent with how this
    /// codebase already prefers generating test data in-code.
    private func writePDF(pageCount: Int, pageSize: CGSize) -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let data = renderer.pdfData { context in
            for _ in 0..<pageCount {
                context.beginPage()
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: pageSize))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try! data.write(to: url)
        return url
    }

    func testRenderPagesOfSinglePagePDFReturnsOneImageCappedAtMaxDimensionPreservingAspectRatio() {
        let pageSize = CGSize(width: 600, height: 800)
        let url = writePDF(pageCount: 1, pageSize: pageSize)

        let images = PDFPageRenderer.renderPages(of: url)

        XCTAssertEqual(images.count, 1)
        guard let image = images.first else { return }
        XCTAssertEqual(max(image.size.width, image.size.height), 2200, accuracy: 1)
        let originalAspect = pageSize.width / pageSize.height
        let renderedAspect = image.size.width / image.size.height
        XCTAssertEqual(originalAspect, renderedAspect, accuracy: 0.01)
    }

    func testRenderPagesReturnsAllPagesWhenUnderCap() {
        let url = writePDF(pageCount: 2, pageSize: CGSize(width: 400, height: 400))

        XCTAssertEqual(PDFPageRenderer.renderPages(of: url).count, 2)
    }

    func testRenderPagesCapsAtMaxPagesForLongerPDFs() {
        let url = writePDF(pageCount: PDFPageRenderer.maxPages + 3, pageSize: CGSize(width: 400, height: 400))

        XCTAssertEqual(PDFPageRenderer.renderPages(of: url).count, PDFPageRenderer.maxPages)
    }

    func testRenderPagesOfCorruptFileReturnsEmptyArray() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try! Data("not a pdf".utf8).write(to: url)

        XCTAssertTrue(PDFPageRenderer.renderPages(of: url).isEmpty)
    }

    func testRenderPagesOfMissingFileReturnsEmptyArray() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")

        XCTAssertTrue(PDFPageRenderer.renderPages(of: url).isEmpty)
    }
}
