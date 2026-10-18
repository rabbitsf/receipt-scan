import XCTest
import PDFKit
@testable import ReceiptTracker

/// Shared test helper: a PDF made in code (no binary fixtures), each page
/// filled with noise when `noisy` so its JPEG isn't trivially small.
enum TestPDF {
    static func make(pageCount: Int, pageSize: CGSize = CGSize(width: 612, height: 792), noisy: Bool = false) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize)).pdfData { context in
            for page in 0..<pageCount {
                context.beginPage()
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: pageSize))
                ("Page \(page + 1)" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 30)])
                if noisy {
                    for _ in 0..<400 {
                        UIColor(hue: .random(in: 0...1), saturation: 1, brightness: 1, alpha: 1).setFill()
                        context.fill(CGRect(x: .random(in: 0...pageSize.width), y: .random(in: 0...pageSize.height), width: 30, height: 30))
                    }
                }
            }
        }
    }

    static func document(pageCount: Int, noisy: Bool = false) -> PDFDocument {
        PDFDocument(data: make(pageCount: pageCount, noisy: noisy))!
    }
}

final class PDFPageRendererTests: XCTestCase {
    func testRendersRequestedPagesAtExactPixelSizePreservingAspect() throws {
        let document = TestPDF.document(pageCount: 3)
        let jpegs = PDFPageRenderer.renderJPEGs(of: document, pages: 0..<2, maxEdge: 2200, quality: 0.8)
        XCTAssertEqual(jpegs.count, 2)
        let image = try XCTUnwrap(UIImage(data: jpegs[0])?.cgImage)
        XCTAssertEqual(image.height, 2200) // pixels, regardless of screen scale
        XCTAssertEqual(Double(image.width) / Double(image.height), 612.0 / 792.0, accuracy: 0.01)
    }

    func testRenderedSizesMatchRenderingWithoutDrawing() {
        let document = TestPDF.document(pageCount: 2)
        let sizes = PDFPageRenderer.renderedSizes(of: document, pages: 0..<2, maxEdge: 2000)
        XCTAssertEqual(sizes.count, 2)
        XCTAssertEqual(sizes[0].height, 2000)
        XCTAssertEqual(sizes[0].width, 1545)
    }

    func testCorruptDataIsNotADocument() {
        XCTAssertNil(PDFDocument(data: Data("not a pdf".utf8)))
    }
}
