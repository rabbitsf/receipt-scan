import XCTest
@testable import ReceiptTracker

final class OCRScanCostTests: XCTestCase {
    // Worked examples from each provider's docs (checked 2026-10-18).

    func testClaudeImageTokensMatchDocsTable() {
        XCTAssertEqual(OCRProvider.anthropic.imageInputTokens(width: 200, height: 200), 64)
        XCTAssertEqual(OCRProvider.anthropic.imageInputTokens(width: 1000, height: 1000), 1296)
        XCTAssertEqual(OCRProvider.anthropic.imageInputTokens(width: 1920, height: 1080), 2691)
        // 4K is downscaled to the 4784-token cap.
        XCTAssertLessThanOrEqual(OCRProvider.anthropic.imageInputTokens(width: 3840, height: 2160), 4784)
        XCTAssertGreaterThan(OCRProvider.anthropic.imageInputTokens(width: 3840, height: 2160), 4500)
    }

    func testOpenAIImageTokensUse32PxPatchesTimes1Point2() {
        // 64×64 = 2×2 patches → 4 × 1.2 = 4.8 → 5
        XCTAssertEqual(OCRProvider.openai.imageInputTokens(width: 64, height: 64), 5)
        // 1700×2200 → 54 × 69 = 3726 patches → 4471.2 → 4472
        XCTAssertEqual(OCRProvider.openai.imageInputTokens(width: 1700, height: 2200), 4472)
    }

    func testGeminiImageTokensUseTiles() {
        XCTAssertEqual(OCRProvider.gemini.imageInputTokens(width: 384, height: 384), 258)
        // Docs example: 960×540 → crop unit 360 → 3 × 2 = 6 tiles
        XCTAssertEqual(OCRProvider.gemini.imageInputTokens(width: 960, height: 540), 6 * 258)
    }

    func testEstimateUsesDefaultModelPriceAndIsNilForCustomModel() {
        let pages = Array(repeating: (width: 1700, height: 2200), count: 10)
        let claude = OCRScanCost.estimate(pageSizes: pages, provider: .anthropic, model: OCRProvider.anthropic.defaultModel)
        XCTAssertEqual(claude.outputTokens, 200 + 1200)
        let expected = (Double(claude.inputTokens) * 5 + Double(claude.outputTokens) * 25) / 1_000_000
        XCTAssertEqual(claude.usd ?? -1, expected, accuracy: 0.000001)
        XCTAssertEqual(claude.usd ?? 0, 0.27, accuracy: 0.03, "10 letter pages on Claude is about a quarter")

        XCTAssertNil(OCRScanCost.estimate(pageSizes: pages, provider: .anthropic, model: "my-custom-model").usd)
    }

    func testPriceSchedules() {
        XCTAssertEqual(OCRProvider.openai.defaultModelPrice(inputTokens: 300_000).input, 4)
        XCTAssertEqual(OCRProvider.openai.defaultModelPrice(inputTokens: 1_000).input, 2)
        let before = OCRScanCost.geminiPriceChange.addingTimeInterval(-60)
        let after = OCRScanCost.geminiPriceChange.addingTimeInterval(60)
        XCTAssertEqual(OCRProvider.gemini.defaultModelPrice(inputTokens: 1, on: before).input, 0.75)
        XCTAssertEqual(OCRProvider.gemini.defaultModelPrice(inputTokens: 1, on: after).input, 1.5)
    }

    func testFormatting() {
        XCTAssertEqual(OCRScanCost.formatted(0.004), "under $0.01")
        XCTAssertEqual(OCRScanCost.formatted(0.256), "~$0.26")
    }
}
