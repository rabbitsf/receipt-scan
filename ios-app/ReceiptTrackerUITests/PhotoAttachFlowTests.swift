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
    /// `AnthropicVisionClientTests.testExtractReceiptsThrowsMissingAPIKeyWhenNoneStored`
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
}
