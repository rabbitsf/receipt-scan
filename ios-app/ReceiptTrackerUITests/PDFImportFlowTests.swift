import XCTest
import UIKit

/// PDF import with several files, the cost popup, and viewing a PDF receipt.
/// The system file picker is replaced by the app's test-only
/// `UITEST_PDF_IMPORT_DIR` folder; UI tests have no API key, so every file's
/// scan fails and becomes a blank entry — which still exercises the
/// multi-file queue, per-entry source labels and attached PDFs. Real scans
/// are checked live, outside the test suite.
final class PDFImportFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makePDFFolder(_ files: [(name: String, pages: Int)]) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in files {
            let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { ctx in
                for page in 1...file.pages {
                    ctx.beginPage()
                    ("\(file.name) p\(page)" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
                }
            }
            try data.write(to: dir.appendingPathComponent(file.name))
        }
        return dir.path
    }

    private func openImportPDF(_ app: XCUIApplication) {
        app.buttons["addReceiptButton"].tap()
        let attach = app.buttons["attachPhotoButton"]
        XCTAssertTrue(attach.waitForExistence(timeout: 5))
        attach.tap()
        let importButton = app.buttons["Import PDF"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()
    }

    func testTwoPDFsShowCostChoicesAndQueueOneEntryPerFile() throws {
        let app = XCUIApplication.receiptTracker()
        app.launchEnvironment["UITEST_PDF_IMPORT_DIR"] = try makePDFFolder([("a-long.pdf", 7), ("b-short.pdf", 2)])
        app.launch()
        openImportPDF(app)

        let alert = app.alerts["Scan 2 PDFs?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS 'a-long.pdf — 7 pages'")).firstMatch.exists)
        let scanAll = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Scan All 9 Pages'")).firstMatch
        XCTAssertTrue(scanAll.exists, "all-pages choice shows the total")
        XCTAssertTrue(alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Scan First 5 Pages of Each'")).firstMatch.exists)
        scanAll.tap()

        let status = app.staticTexts["queueStatusText"]
        XCTAssertTrue(status.waitForExistence(timeout: 30))
        XCTAssertTrue(status.label.contains("reviewing receipt 1 of 2"), status.label)
        XCTAssertEqual(app.staticTexts["sourceLabelText"].label, "From a-long.pdf")
        XCTAssertTrue(app.staticTexts["pdfBadge"].label.contains("7 pages"))

        // Fill in the first entry by hand and move to the second file's entry.
        let merchant = app.textFields["merchantField"]
        merchant.tap()
        merchant.typeText("PDF One")
        let total = app.textFields["totalCostField"]
        total.tap()
        total.typeText("1")
        app.buttons["saveReceiptButton"].tap()

        XCTAssertTrue(app.staticTexts["sourceLabelText"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sourceLabelText"].label, "From b-short.pdf")
        // Typing scrolled the form; the badge row is at the top (off-screen rows aren't in the hierarchy).
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["pdfBadge"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["pdfBadge"].label.contains("2 pages"))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["PDF One"].waitForExistence(timeout: 5))
    }

    func testCancelInCostPopupScansNothing() throws {
        let app = XCUIApplication.receiptTracker()
        app.launchEnvironment["UITEST_PDF_IMPORT_DIR"] = try makePDFFolder([("only.pdf", 2)])
        app.launch()
        openImportPDF(app)

        let alert = app.alerts["Scan This PDF?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertFalse(alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Scan First'")).firstMatch.exists,
                       "no first-pages choice when the file is short")
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["pdfBadge"].waitForExistence(timeout: 2))
    }

    func testViewingAPDFReceiptShowsPagesAndShare() throws {
        let merchant = "PDFView \(UUID().uuidString.prefix(6))"
        let app = XCUIApplication.receiptTracker()
        app.launchEnvironment["UITEST_SEED_PDF_MERCHANT"] = merchant
        app.launch()

        let row = app.staticTexts[merchant]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        let view = app.buttons["viewReceiptButton"]
        XCTAssertTrue(view.waitForExistence(timeout: 5))
        view.tap()

        XCTAssertTrue(app.navigationBars["Receipt PDF"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sharePDFButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["savePhotoButton"].exists)
        app.buttons["closeReceiptImageButton"].tap()
    }
}
