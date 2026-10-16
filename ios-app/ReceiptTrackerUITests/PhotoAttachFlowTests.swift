import XCTest

final class PhotoAttachFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Confirms the photo-source dialog opens and always offers "Choose
    /// from Library". (This Simulator/Xcode version reports the camera as
    /// available too, unlike older Simulator versions, so "Take Photo" may
    /// or may not appear here — that reflects
    /// `UIImagePickerController.isSourceTypeAvailable(.camera)`'s actual
    /// return value, which the app correctly defers to rather than
    /// hardcoding an assumption; not something to assert on in this test.)
    ///
    /// A companion test that drove the real system Photos picker end-to-end
    /// (select a seeded photo → confirm the app's "no API key" notice) was
    /// removed after proving flaky/non-deterministic across runs — not a
    /// timing issue fixable with better waits, but the picker sheet
    /// transition intermittently sending the whole app to the Home Screen
    /// mid-test (observed via a mid-test screenshot). Automating
    /// PHPickerViewController via XCUITest is a known-fragile area on
    /// iOS/Simulator. The behavior that test would have covered is already
    /// verified two other ways that don't share this fragility:
    /// `ReceiptExtractorTests.testExtractReceiptsThrowsMissingAPIKeyWhenNoneStored`
    /// (fast, deterministic unit test) and the user's own real-device,
    /// real-photo, real-API-key manual verification (2026-07-23).
    func testPhotoSourceDialogOffersLibraryOption() throws {
        let app = XCUIApplication()
        // Ensure a clean process, not a re-foregrounded one with leftover
        // sheet/dialog state from a previous test in this run.
        app.terminate()
        app.launch()

        app.buttons["addReceiptButton"].tap()

        let attachButton = app.buttons["attachPhotoButton"]
        XCTAssertTrue(attachButton.waitForExistence(timeout: 10))
        attachButton.tap()

        XCTAssertTrue(app.buttons["Choose from Library"].waitForExistence(timeout: 5))
    }

    /// Confirms the same dialog also offers "Import PDF" — same
    /// dialog-presence-only scope as the test above, for the same reason:
    /// don't attempt to automate the system document picker sheet itself
    /// in XCUITest (same fragility class as the removed Photos-picker test
    /// documented above). The render pipeline
    /// (`PDFPageRenderer.renderFirstPage(of:)`) and the "only first page
    /// scanned" warning alert are covered by `PDFPageRendererTests.swift`
    /// (unit) and manual real-device verification instead.
    func testPhotoSourceDialogOffersImportPDFOption() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launch()

        app.buttons["addReceiptButton"].tap()

        let attachButton = app.buttons["attachPhotoButton"]
        XCTAssertTrue(attachButton.waitForExistence(timeout: 10))
        attachButton.tap()

        XCTAssertTrue(app.buttons["Import PDF"].waitForExistence(timeout: 5))
    }
}
