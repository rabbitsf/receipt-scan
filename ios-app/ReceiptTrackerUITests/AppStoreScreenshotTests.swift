import XCTest

/// App Store screenshots with made-up demo receipts (`DemoData`). Runs only
/// when a folder is given: `TEST_RUNNER_SCREENSHOT_DIR=<folder> xcodebuild
/// test -only-testing:ReceiptTrackerUITests/AppStoreScreenshotTests …`.
/// Skipped in normal test runs.
final class AppStoreScreenshotTests: XCTestCase {
    private var dir: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Screenshots are only taken when SCREENSHOT_DIR is set")
        }
        self.dir = dir
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    private func save(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2) // let animations settle
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir!)/\(name).png"))
    }

    private func launchDemo(importDir: String? = nil) -> XCUIApplication {
        let app = XCUIApplication.receiptTracker()
        app.launchEnvironment["UITEST_DEMO_DATA"] = "1"
        if let importDir { app.launchEnvironment["UITEST_PDF_IMPORT_DIR"] = importDir }
        app.launch()
        XCTAssertTrue(app.staticTexts["Harbor Coffee Roasters"].waitForExistence(timeout: 10))
        return app
    }

    func testTakeScreenshots() throws {
        let importDir = NSTemporaryDirectory() + "demo-import-\(UUID().uuidString)"
        let app = launchDemo(importDir: importDir)

        // 1. Receipt list — wait out one-time system banners (e.g. a fresh
        // simulator's "Ready for Apple Intelligence") first.
        Thread.sleep(forTimeInterval: 8)
        save("01 Receipts")

        // 2. Dashboard
        app.buttons["dashboardButton"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        save("02 Dashboard")
        app.buttons["Done"].tap()

        // 3. A receipt with its photo
        app.staticTexts["Summit Office Supply"].firstMatch.tap()
        XCTAssertTrue(app.textFields["merchantField"].waitForExistence(timeout: 5))
        save("03 Receipt Details")
        app.buttons["Cancel"].tap()

        // 4. Multi-receipt PDF kept as a PDF
        let hotel = app.staticTexts["Lakeside Grand Hotel"].firstMatch
        XCTAssertTrue(hotel.waitForExistence(timeout: 5))
        hotel.swipeLeft()
        app.buttons["viewReceiptButton"].tap()
        XCTAssertTrue(app.navigationBars["Receipt PDF"].waitForExistence(timeout: 5))
        save("04 Receipt PDF")
        app.buttons["closeReceiptImageButton"].tap()

        // 5. Import several PDFs — cost estimate first
        app.buttons["addReceiptButton"].tap()
        app.buttons["attachPhotoButton"].tap()
        app.buttons["Import PDF"].tap()
        XCTAssertTrue(app.alerts["Scan 2 PDFs?"].waitForExistence(timeout: 10))
        save("05 Import PDFs")
        app.alerts["Scan 2 PDFs?"].buttons["Cancel"].tap()
        app.buttons["Cancel"].tap()

        // 6. Filter by group
        app.buttons["filterButton"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        save("06 Filters")
        app.buttons["Done"].tap()

        // 7. Web Access over Wi-Fi
        app.buttons["settingsButton"].tap()
        let toggle = app.switches["webAccessToggle"]
        toggle.scrolledIntoView(in: app)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        if !app.staticTexts["webAccessCode"].waitForExistence(timeout: 3) { app.staticTexts["webAccessCode"].scrolledIntoView(in: app) }
        XCTAssertTrue(app.staticTexts["webAccessCode"].waitForExistence(timeout: 5))
        save("07 Web Access")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
}
