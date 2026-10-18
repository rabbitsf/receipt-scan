import XCTest
@testable import ReceiptTracker

final class ReceiptExtractorTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ReceiptExtractorTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        OCRProvider.allCases.forEach { APIKeyStore.delete(for: $0) }
        super.tearDown()
    }

    // MARK: - Dispatcher

    func testExtractReceiptsThrowsMissingAPIKeyWhenNoneStored() async throws {
        for provider in OCRProvider.allCases {
            APIKeyStore.delete(for: provider)
            do {
                _ = try await ReceiptExtractor.extractReceipts(images: [Data()], mediaType: "image/jpeg", provider: provider)
                XCTFail("Expected missingAPIKey error for \(provider)")
            } catch let error as OCRError {
                XCTAssertEqual(error, .missingAPIKey(providerName: provider.displayName))
                XCTAssertEqual(error.errorDescription, "No \(provider.displayName) API key set. Add one in Settings to scan receipts.")
            }
        }
    }

    /// A key saved for a different provider must not be used.
    func testExtractReceiptsDoesNotFallBackToAnotherProvidersKey() async throws {
        try APIKeyStore.save("anthropic-key", for: .anthropic)
        do {
            _ = try await ReceiptExtractor.extractReceipts(images: [Data()], mediaType: "image/jpeg", provider: .gemini)
            XCTFail("Expected missingAPIKey error")
        } catch let error as OCRError {
            XCTAssertEqual(error, .missingAPIKey(providerName: "Gemini"))
        }
    }

    /// With a key but without the user's permission, nothing is sent.
    func testExtractReceiptsRequiresPermissionBeforeSending() async throws {
        try APIKeyStore.save("sk-ant-test", for: .anthropic)
        do {
            _ = try await ReceiptExtractor.extractReceipts(images: [Data()], mediaType: "image/jpeg", provider: .anthropic, hasConsent: { _ in false })
            XCTFail("Expected consentRequired error")
        } catch let error as OCRError {
            XCTAssertEqual(error, .consentRequired(providerName: "Claude"))
        }
    }

    func testConsentIsPerProviderAndRevocable() {
        XCTAssertFalse(AIScanConsent.isGranted(for: .openai, defaults: defaults))
        AIScanConsent.set(true, for: .openai, defaults: defaults)
        XCTAssertTrue(AIScanConsent.isGranted(for: .openai, defaults: defaults))
        XCTAssertFalse(AIScanConsent.isGranted(for: .gemini, defaults: defaults))
        AIScanConsent.set(false, for: .openai, defaults: defaults)
        XCTAssertFalse(AIScanConsent.isGranted(for: .openai, defaults: defaults))
        XCTAssertTrue(AIScanConsent.explanation(for: .gemini).contains("Google (Gemini)"))
    }

    func testExtractReceiptsThrowsInvalidResponseForEmptyImages() async throws {
        do {
            _ = try await ReceiptExtractor.extractReceipts(images: [], mediaType: "image/jpeg")
            XCTFail("Expected invalidResponse error")
        } catch OCRError.invalidResponse {
            // expected
        }
    }

    func testEachProviderRoutesToItsOwnClient() {
        XCTAssertTrue(OCRProvider.anthropic.client == AnthropicVisionClient.self)
        XCTAssertTrue(OCRProvider.openai.client == OpenAIVisionClient.self)
        XCTAssertTrue(OCRProvider.gemini.client == GeminiVisionClient.self)
    }

    // MARK: - OCRSettings

    func testSelectedProviderDefaultsToClaude() {
        XCTAssertEqual(OCRSettings.selectedProvider(defaults: defaults), .anthropic)
    }

    func testSelectedProviderRoundTrips() {
        OCRSettings.setSelectedProvider(.gemini, defaults: defaults)
        XCTAssertEqual(OCRSettings.selectedProvider(defaults: defaults), .gemini)
    }

    func testEffectiveModelFallsBackToDefault() {
        for provider in OCRProvider.allCases {
            XCTAssertNil(OCRSettings.modelOverride(for: provider, defaults: defaults))
            XCTAssertEqual(OCRSettings.effectiveModel(for: provider, defaults: defaults), provider.defaultModel)
        }
    }

    func testModelOverrideIsPerProviderAndTrimmed() {
        OCRSettings.setModelOverride("  gpt-custom  ", for: .openai, defaults: defaults)

        XCTAssertEqual(OCRSettings.effectiveModel(for: .openai, defaults: defaults), "gpt-custom")
        XCTAssertEqual(OCRSettings.effectiveModel(for: .gemini, defaults: defaults), OCRProvider.gemini.defaultModel)
    }

    func testBlankModelOverrideRestoresDefault() {
        OCRSettings.setModelOverride("gpt-custom", for: .openai, defaults: defaults)
        OCRSettings.setModelOverride("   ", for: .openai, defaults: defaults)

        XCTAssertNil(OCRSettings.modelOverride(for: .openai, defaults: defaults))
        XCTAssertEqual(OCRSettings.effectiveModel(for: .openai, defaults: defaults), OCRProvider.openai.defaultModel)
    }

    // MARK: - Missing-key launch warning

    func testMissingKeyWarningShowsWhenSelectedProviderHasNoKey() {
        XCTAssertTrue(OCRSettings.shouldShowMissingKeyWarning(defaults: defaults, hasKey: { _ in false }))
    }

    func testMissingKeyWarningHiddenWhenSelectedProviderHasKey() {
        XCTAssertFalse(OCRSettings.shouldShowMissingKeyWarning(defaults: defaults, hasKey: { _ in true }))
    }

    /// Only the *selected* provider's key matters — a Claude key doesn't
    /// help when Gemini is the one that will be used to scan.
    func testMissingKeyWarningChecksTheSelectedProvider() {
        OCRSettings.setSelectedProvider(.gemini, defaults: defaults)
        XCTAssertTrue(OCRSettings.shouldShowMissingKeyWarning(defaults: defaults, hasKey: { $0 == .anthropic }))
        XCTAssertFalse(OCRSettings.shouldShowMissingKeyWarning(defaults: defaults, hasKey: { $0 == .gemini }))
    }

    func testDontShowAgainSilencesMissingKeyWarning() {
        XCTAssertFalse(OCRSettings.keyWarningDismissed(defaults: defaults))
        OCRSettings.dismissKeyWarning(defaults: defaults)
        XCTAssertTrue(OCRSettings.keyWarningDismissed(defaults: defaults))
        XCTAssertFalse(OCRSettings.shouldShowMissingKeyWarning(defaults: defaults, hasKey: { _ in false }))
    }
}
