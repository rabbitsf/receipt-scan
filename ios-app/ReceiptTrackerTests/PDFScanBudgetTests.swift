import XCTest
import PDFKit
@testable import ReceiptTracker

final class PDFScanBudgetTests: XCTestCase {
    // MARK: - Budget

    func testRendersSmallerAboveTwentyPages() {
        XCTAssertEqual(PDFScanBudget.steps(pageCount: 20).first?.maxEdge, 2200)
        XCTAssertEqual(PDFScanBudget.steps(pageCount: 21).first?.maxEdge, 2000)
    }

    func testFitsChecksBothSizeAndImageCount() {
        XCTAssertTrue(PDFScanBudget.fitsInOneRequest(imageByteCounts: [1_000_000, 1_000_000], provider: .anthropic))
        // 20 MB of images = ~26.7 MB base64: fits Claude (32 MB) but not Gemini (20 MB).
        let big = Array(repeating: 1_000_000, count: 20)
        XCTAssertTrue(PDFScanBudget.fitsInOneRequest(imageByteCounts: big, provider: .anthropic))
        XCTAssertFalse(PDFScanBudget.fitsInOneRequest(imageByteCounts: big, provider: .gemini))
        XCTAssertFalse(PDFScanBudget.fitsInOneRequest(imageByteCounts: Array(repeating: 10, count: 601), provider: .anthropic))
    }

    func testPartsAreConsecutiveAndEachFits() {
        let counts = Array(repeating: 1_000_000, count: 50) // ~67 MB base64
        let parts = PDFScanBudget.parts(imageByteCounts: counts, provider: .gemini)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.first?.lowerBound, 0)
        XCTAssertEqual(parts.last?.upperBound, 50)
        for (a, b) in zip(parts, parts.dropFirst()) { XCTAssertEqual(a.upperBound, b.lowerBound) }
        for part in parts {
            XCTAssertTrue(PDFScanBudget.fitsInOneRequest(imageByteCounts: Array(counts[part]), provider: .gemini))
        }
    }

    func testPrepareUsesOneRequestForSmallFiles() {
        let prepared = PDFScanBudget.prepare(document: TestPDF.document(pageCount: 3), pageCount: 3, provider: .anthropic)
        XCTAssertEqual(prepared.images.count, 3)
        XCTAssertEqual(prepared.parts, [0..<3])
        XCTAssertFalse(prepared.wasShrunk)
    }

    func testPrepareOnlyRendersRequestedLeadingPages() {
        let prepared = PDFScanBudget.prepare(document: TestPDF.document(pageCount: 8), pageCount: 5, provider: .gemini)
        XCTAssertEqual(prepared.images.count, 5)
    }

    // MARK: - Page assignment

    func testSingleReceiptKeepsEveryPageEvenUnscannedOnes() {
        let result = PDFPageAssignment.assign(receiptPages: [[1]], scannedPageCount: 5, totalPageCount: 8)
        XCTAssertEqual(result.pagesPerReceipt, [Array(1...8)])
        XCTAssertEqual(result.unkeptPages, [])
    }

    func testSeveralReceiptsKeepTheirOwnValidPagesSortedAndUnique() {
        let result = PDFPageAssignment.assign(receiptPages: [[2, 1, 2], [3], [3, 9]], scannedPageCount: 3, totalPageCount: 3)
        XCTAssertEqual(result.pagesPerReceipt, [[1, 2], [3], [3]])
        XCTAssertEqual(result.unkeptPages, [])
    }

    func testReceiptWithNoUsablePagesKeepsWholeFile() {
        let result = PDFPageAssignment.assign(receiptPages: [[], [0, 7], [2]], scannedPageCount: 3, totalPageCount: 3)
        XCTAssertEqual(result.pagesPerReceipt, [[1, 2, 3], [1, 2, 3], [2]])
    }

    func testFirstFiveWithSeveralReceiptsReportsUnkeptPages() {
        let result = PDFPageAssignment.assign(receiptPages: [[1, 2], [5, 6]], scannedPageCount: 5, totalPageCount: 7)
        XCTAssertEqual(result.pagesPerReceipt, [[1, 2], [5]])
        XCTAssertEqual(result.unkeptPages, [6, 7])
    }

    func testPartPagesMapToFilePositions() {
        XCTAssertEqual(PDFPageAssignment.filePages([1, 3, 9], part: 10..<15), [11, 13])
    }

    func testLabels() {
        XCTAssertEqual(PDFPageAssignment.label([2]), "page 2")
        XCTAssertEqual(PDFPageAssignment.label([1, 2, 3]), "pages 1–3")
        XCTAssertEqual(PDFPageAssignment.label([1, 3]), "pages 1, 3")
    }

    // MARK: - Subset

    func testSubsetKeepsOnlyChosenPagesInOrderAndWholeFileIsUnchanged() throws {
        let original = TestPDF.make(pageCount: 4)
        let document = try XCTUnwrap(PDFDocument(data: original))

        let subset = try XCTUnwrap(PDFSubset.data(of: document, originalData: original, pages: [2, 4]))
        let subsetDocument = try XCTUnwrap(PDFDocument(data: subset))
        XCTAssertEqual(subsetDocument.pageCount, 2)
        XCTAssertEqual(subsetDocument.page(at: 0)?.string?.contains("Page 2"), true)
        XCTAssertEqual(subsetDocument.page(at: 1)?.string?.contains("Page 4"), true)

        XCTAssertEqual(PDFSubset.data(of: document, originalData: original, pages: [1, 2, 3, 4]), original)
        XCTAssertNil(PDFSubset.data(of: document, originalData: original, pages: [9]))
    }
}
