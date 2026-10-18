import XCTest
import PDFKit
@testable import ReceiptTracker

final class PDFImportScannerTests: XCTestCase {
    private func file(_ name: String, pages: Int) -> PDFImportScanner.File {
        PDFImportScanner.File(name: name, data: TestPDF.make(pageCount: pages))
    }

    private func pageCount(_ data: Data?) -> Int? {
        data.flatMap { PDFDocument(data: $0)?.pageCount }
    }

    func testEachFileScannedSeparatelyAndReceiptsKeepTheirOwnPages() async {
        let calls = CallLog()
        let items = await PDFImportScanner.scan(
            files: [file("a.pdf", pages: 3), file("b.pdf", pages: 1)],
            scope: .allPages,
            provider: .anthropic,
            extract: { images in
                await calls.add(images.count)
                if images.count == 3 {
                    return [ExtractedReceipt(date: "2026-01-01", merchant: "A1", totalCost: 1, description: "", pages: [1, 2]),
                            ExtractedReceipt(date: "2026-01-02", merchant: "A2", totalCost: 2, description: "", pages: [3])]
                }
                return [ExtractedReceipt(date: "2026-01-03", merchant: "B", totalCost: 3, description: "", pages: [1])]
            }
        )
        let counts = await calls.counts
        XCTAssertEqual(counts, [3, 1], "one request per file")
        XCTAssertEqual(items.map { $0.fields?.merchant }, ["A1", "A2", "B"])
        XCTAssertEqual(items.map(\.sourceLabel), ["From a.pdf · pages 1–2", "From a.pdf · page 3", "From b.pdf · page 1"])
        XCTAssertEqual(items.map { pageCount($0.pdfData) }, [2, 1, 1])
        XCTAssertNotNil(items[0].imageData)
    }

    func testFirstPagesScopeScansOnlyThoseAndReportsUnkeptPages() async {
        let items = await PDFImportScanner.scan(
            files: [file("long.pdf", pages: 8)],
            scope: .firstPages(5),
            provider: .anthropic,
            extract: { images in
                XCTAssertEqual(images.count, 5)
                return [ExtractedReceipt(date: "", merchant: "X", totalCost: 1, description: "", pages: [1]),
                        ExtractedReceipt(date: "", merchant: "Y", totalCost: 2, description: "", pages: [4, 5])]
            }
        )
        XCTAssertEqual(items.map { pageCount($0.pdfData) }, [1, 2])
        XCTAssertTrue(items[0].notices.contains { $0.contains("Pages 6–8 of long.pdf") })
    }

    func testFailuresBecomeBlankEntriesWithTheWholeFile() async {
        struct Boom: Error {}
        let items = await PDFImportScanner.scan(
            files: [file("bad.pdf", pages: 2), PDFImportScanner.File(name: "junk.pdf", data: Data("nope".utf8))],
            scope: .allPages,
            provider: .anthropic,
            extract: { _ in throw Boom() }
        )
        XCTAssertEqual(items.count, 2)
        XCTAssertNil(items[0].fields)
        XCTAssertEqual(pageCount(items[0].pdfData), 2)
        XCTAssertTrue(items[0].notices.first?.contains("Scanning bad.pdf failed") == true)
        XCTAssertTrue(items[1].notices.first?.contains("Couldn't read junk.pdf") == true)
    }

    func testCostSummaryCountsPagesAndEstimates() {
        let files = [file("a.pdf", pages: 8), file("b.pdf", pages: 2)]
        let claude = PDFImportScanner.costSummary(files: files, provider: .anthropic, model: OCRProvider.anthropic.defaultModel)
        XCTAssertEqual(claude.totalPages, 10)
        XCTAssertEqual(claude.quickScanPages, 7)
        XCTAssertGreaterThan(claude.allPagesUSD ?? 0, claude.quickScanUSD ?? .infinity)
        XCTAssertEqual(claude.files.map(\.pages), [8, 2])

        let custom = PDFImportScanner.costSummary(files: files, provider: .anthropic, model: "custom")
        XCTAssertNil(custom.allPagesUSD)
    }
}

private actor CallLog {
    var counts: [Int] = []
    func add(_ count: Int) { counts.append(count) }
}
