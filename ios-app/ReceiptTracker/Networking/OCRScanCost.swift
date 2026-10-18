import Foundation

/// Request limits, image token formulas and default-model prices for each
/// scanning provider — THE table behind the PDF import cost popup and the
/// page budget (`PDFScanBudget`). Mirrors `OCR_PROVIDERS` in
/// `backend/src/services/ocrService.js`; change both together.
///
/// Checked 2026-10-18 against each provider's docs:
/// - Claude: platform.claude.com/docs/en/build-with-claude/vision (+ Anthropic pricing)
/// - OpenAI: developers.openai.com/docs/guides/images-vision, /api/docs/pricing
/// - Gemini: ai.google.dev/gemini-api/docs/image-understanding, /pricing
extension OCRProvider {
    /// Most images one request may carry.
    var maxImagesPerRequest: Int {
        switch self {
        case .anthropic: return 600
        case .openai: return 1500
        case .gemini: return 3600
        }
    }

    /// Largest request body, in bytes (images are sent base64-encoded).
    var maxRequestBytes: Int {
        switch self {
        case .anthropic: return 32 * 1024 * 1024
        case .openai: return 512 * 1024 * 1024
        case .gemini: return 20 * 1024 * 1024
        }
    }

    /// Approximate input tokens one image of this size costs, using the
    /// provider's published formula for its default model.
    func imageInputTokens(width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let w = Double(width)
        let h = Double(height)
        switch self {
        case .anthropic:
            // High-resolution tier (Claude 4.7 and later): 28 px patches,
            // long edge ≤ 2576 px, ≤ 4784 patches; larger images are downscaled.
            let patches = { (w: Double, h: Double) in (w / 28).rounded(.up) * (h / 28).rounded(.up) }
            var scale = min(1, 2576 / max(w, h))
            if patches(w * scale, h * scale) > 4784 {
                scale *= (4784 / patches(w * scale, h * scale)).squareRoot()
            }
            return Int(min(4784, patches(w * scale, h * scale)))
        case .openai:
            // 32 px patches × 1.2 at the default (original) detail, capped at 30,000 patches.
            let patches = min(30_000, (w / 32).rounded(.up) * (h / 32).rounded(.up))
            return Int((patches * 1.2).rounded(.up))
        case .gemini:
            // ≤ 384 px both ways: one 258-token tile; else tiles of floor(min side / 1.5).
            if w <= 384, h <= 384 { return 258 }
            let crop = (min(w, h) / 1.5).rounded(.down)
            return Int((w / crop).rounded(.up) * (h / crop).rounded(.up)) * 258
        }
    }

    /// USD per 1M tokens for the provider's DEFAULT model, on `date`, for a
    /// request with `inputTokens` input tokens.
    func defaultModelPrice(inputTokens: Int, on date: Date = Date()) -> (input: Double, output: Double) {
        switch self {
        case .anthropic:
            return (5, 25)
        case .openai:
            return inputTokens > 272_000 ? (4, 15) : (2, 10)
        case .gemini:
            return date < OCRScanCost.geminiPriceChange ? (0.75, 3.75) : (1.5, 7.5)
        }
    }
}

enum OCRScanCost {
    struct Estimate: Equatable {
        let inputTokens: Int
        let outputTokens: Int
        /// nil when a custom model is set in Settings (its price isn't known).
        let usd: Double?
    }

    /// Gemini Flash price doubles on 2027-01-01 (per Google's pricing page).
    static let geminiPriceChange = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"), year: 2027, month: 1, day: 1).date!

    /// Prompt and schema text sent with every scan.
    static let promptTokens = 600
    /// Rough answer size: a fixed part plus one receipt's worth per page.
    static let baseOutputTokens = 200
    static let outputTokensPerPage = 120

    static func estimate(
        pageSizes: [(width: Int, height: Int)],
        provider: OCRProvider,
        model: String,
        on date: Date = Date()
    ) -> Estimate {
        let input = promptTokens + pageSizes.reduce(0) { $0 + provider.imageInputTokens(width: $1.width, height: $1.height) }
        let output = baseOutputTokens + outputTokensPerPage * pageSizes.count
        guard model == provider.defaultModel else {
            return Estimate(inputTokens: input, outputTokens: output, usd: nil)
        }
        let price = provider.defaultModelPrice(inputTokens: input, on: date)
        let usd = (Double(input) * price.input + Double(output) * price.output) / 1_000_000
        return Estimate(inputTokens: input, outputTokens: output, usd: usd)
    }

    /// "~$0.12", or "under $0.01" for tiny amounts.
    static func formatted(_ usd: Double) -> String {
        usd < 0.01 ? "under $0.01" : String(format: "~$%.2f", usd)
    }
}
