// Request limits, image token formulas and default-model prices per scanning
// provider — THE table behind the PDF import cost popup and page budget on
// the web. Mirrors iOS's `OCRScanCost.swift`; change both together.
//
// Checked 2026-10-18 against each provider's docs:
// - Claude: platform.claude.com/docs/en/build-with-claude/vision (+ Anthropic pricing)
// - OpenAI: developers.openai.com/docs/guides/images-vision, /api/docs/pricing
// - Gemini: ai.google.dev/gemini-api/docs/image-understanding, /pricing

export const PROVIDER_LIMITS = {
  anthropic: { maxImagesPerRequest: 600, maxRequestBytes: 32 * 1024 * 1024 },
  openai: { maxImagesPerRequest: 1500, maxRequestBytes: 512 * 1024 * 1024 },
  gemini: { maxImagesPerRequest: 3600, maxRequestBytes: 20 * 1024 * 1024 },
};

// Gemini Flash price doubles on 2027-01-01 (per Google's pricing page).
export const GEMINI_PRICE_CHANGE = Date.UTC(2027, 0, 1);

export const PROMPT_TOKENS = 600;
export const BASE_OUTPUT_TOKENS = 200;
export const OUTPUT_TOKENS_PER_PAGE = 120;

// Approximate input tokens one image of this size costs, using the
// provider's published formula for its default model.
export function imageInputTokens(provider, width, height) {
  if (!(width > 0 && height > 0)) return 0;
  switch (provider) {
    case 'anthropic': {
      // High-resolution tier (Claude 4.7+): 28 px patches, long edge ≤ 2576, ≤ 4784 patches.
      const patches = (w, h) => Math.ceil(w / 28) * Math.ceil(h / 28);
      let scale = Math.min(1, 2576 / Math.max(width, height));
      if (patches(width * scale, height * scale) > 4784) {
        scale *= Math.sqrt(4784 / patches(width * scale, height * scale));
      }
      return Math.min(4784, patches(width * scale, height * scale));
    }
    case 'openai': {
      // 32 px patches × 1.2 at the default (original) detail, capped at 30,000 patches.
      const patches = Math.min(30000, Math.ceil(width / 32) * Math.ceil(height / 32));
      return Math.ceil(patches * 1.2);
    }
    case 'gemini': {
      // ≤ 384 px both ways: one 258-token tile; else tiles of floor(min side / 1.5).
      if (width <= 384 && height <= 384) return 258;
      const crop = Math.floor(Math.min(width, height) / 1.5);
      return Math.ceil(width / crop) * Math.ceil(height / crop) * 258;
    }
    default:
      return 0;
  }
}

// USD per 1M tokens for the provider's DEFAULT model.
export function defaultModelPrice(provider, inputTokens, now = Date.now()) {
  switch (provider) {
    case 'anthropic':
      return { input: 5, output: 25 };
    case 'openai':
      return inputTokens > 272000 ? { input: 4, output: 15 } : { input: 2, output: 10 };
    case 'gemini':
      return now < GEMINI_PRICE_CHANGE ? { input: 0.75, output: 3.75 } : { input: 1.5, output: 7.5 };
    default:
      return null;
  }
}

// `usd` is null when a custom model is in use (its price isn't known).
export function estimateScanCost({ pageSizes, provider, isDefaultModel, now = Date.now() }) {
  const inputTokens = PROMPT_TOKENS + pageSizes.reduce((sum, p) => sum + imageInputTokens(provider, p.width, p.height), 0);
  const outputTokens = BASE_OUTPUT_TOKENS + OUTPUT_TOKENS_PER_PAGE * pageSizes.length;
  if (!isDefaultModel) return { inputTokens, outputTokens, usd: null };
  const price = defaultModelPrice(provider, inputTokens, now);
  return { inputTokens, outputTokens, usd: (inputTokens * price.input + outputTokens * price.output) / 1e6 };
}
