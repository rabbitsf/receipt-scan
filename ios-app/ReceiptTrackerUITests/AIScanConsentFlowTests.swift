import XCTest
import UIKit

/// The AI permission prompt (App Store guideline 5.1.2(i)): with a key saved
/// but no permission yet, importing a PDF asks first; "Don't Allow" sends
/// nothing. Built without `receiptTracker()`'s pre-granted permission.
final class AIScanConsentFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPermissionIsAskedBeforeScanningAndCanBeDeclined() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("consent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { ctx in ctx.beginPage() }
        try pdf.write(to: dir.appendingPathComponent("r.pdf"))

        let app = XCUIApplication()
        app.launchArguments += ["-ocrKeyWarningDismissed", "YES", "-ocrProvider", "anthropic"]
        app.launchEnvironment["UITEST_PDF_IMPORT_DIR"] = dir.path
        app.launch()

        // A (fake) key, so a scan would really be sent.
        app.buttons["settingsButton"].tap()
        let field = app.secureTextFields["apiKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("sk-ant-consent-test")
        app.buttons["saveAPIKeyButton"].tap()
        let toggle = app.switches["aiConsentToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "permission starts off")
        app.buttons["Close"].tap()

        app.buttons["addReceiptButton"].tap()
        app.buttons["attachPhotoButton"].tap()
        app.buttons["Import PDF"].tap()

        let prompt = app.alerts["Send Receipts to Claude?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        XCTAssertTrue(prompt.staticTexts.containing(NSPredicate(format: "label CONTAINS 'sent to Anthropic'")).firstMatch.exists)
        prompt.buttons["Don't Allow"].tap()
        XCTAssertFalse(app.alerts["Scan This PDF?"].waitForExistence(timeout: 2), "nothing is scanned without permission")
        app.buttons["Cancel"].tap()

        // Clean up the fake key.
        app.buttons["settingsButton"].tap()
        if app.buttons["removeAPIKeyButton"].waitForExistence(timeout: 5) { app.buttons["removeAPIKeyButton"].tap() }
    }
}
