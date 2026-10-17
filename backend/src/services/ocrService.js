import fs from 'node:fs';
import path from 'node:path';
import * as anthropic from './ocrProviders/anthropic.js';
import * as openai from './ocrProviders/openai.js';
import * as gemini from './ocrProviders/gemini.js';
import { getSetting, setSetting, deleteSetting } from './settingsRepository.js';

// The OCR providers selectable in Settings. Each adapter in `ocrProviders/`
// owns only its wire format; prompt, schema and response parsing below are
// shared so switching providers never changes what gets extracted. Mirrors
// iOS's `OCRProvider.swift`. API keys come from env vars only (never the DB).
export const OCR_PROVIDERS = {
  anthropic: { displayName: 'Claude', defaultModel: 'claude-opus-4-8', envVar: 'ANTHROPIC_API_KEY', adapter: anthropic },
  openai: { displayName: 'OpenAI', defaultModel: 'gpt-6.1-sol', envVar: 'OPENAI_API_KEY', adapter: openai },
  gemini: { displayName: 'Gemini', defaultModel: 'gemini-3.8-flash', envVar: 'GEMINI_API_KEY', adapter: gemini },
};
const DEFAULT_PROVIDER = 'anthropic';
const PROVIDER_SETTING = 'ocr.provider';
const KEY_WARNING_DISMISSED_SETTING = 'ocr.keyWarningDismissed';
const modelSettingKey = (provider) => `ocr.model.${provider}`;

// `models` holds only the user's overrides ('' = use the default), so the
// UI can show the default as a placeholder. `configured` reports whether each
// provider's env var is set — never the key itself. `keyWarningDismissed` is
// the launch popup's "Don't show again" (mirrors iOS's
// `OCRSettings.keyWarningDismissed`).
export function getOcrSettings() {
  const stored = getSetting(PROVIDER_SETTING);
  const provider = OCR_PROVIDERS[stored] ? stored : DEFAULT_PROVIDER;
  const providers = Object.fromEntries(
    Object.entries(OCR_PROVIDERS).map(([id, p]) => [
      id,
      {
        displayName: p.displayName,
        defaultModel: p.defaultModel,
        model: getSetting(modelSettingKey(id)) || '',
        envVar: p.envVar,
        configured: Boolean(process.env[p.envVar]),
      },
    ]),
  );
  return { provider, providers, keyWarningDismissed: getSetting(KEY_WARNING_DISMISSED_SETTING) === 'true' };
}

// `models` is optional and partial: { openai: 'gpt-x' } overrides one
// provider; a blank string clears that override back to the default.
export function updateOcrSettings({ provider, models = {}, keyWarningDismissed }) {
  if (keyWarningDismissed !== undefined) {
    if (typeof keyWarningDismissed !== 'boolean') throw new Error('keyWarningDismissed must be a boolean');
    if (keyWarningDismissed) setSetting(KEY_WARNING_DISMISSED_SETTING, 'true');
    else deleteSetting(KEY_WARNING_DISMISSED_SETTING);
  }
  if (provider !== undefined) {
    if (!OCR_PROVIDERS[provider]) throw new Error(`Unknown OCR provider: ${provider}`);
    setSetting(PROVIDER_SETTING, provider);
  }
  for (const [id, model] of Object.entries(models)) {
    if (!OCR_PROVIDERS[id]) throw new Error(`Unknown OCR provider: ${id}`);
    if (typeof model !== 'string') throw new Error('Model must be a string');
    const trimmed = model.trim();
    if (trimmed) setSetting(modelSettingKey(id), trimmed);
    else deleteSetting(modelSettingKey(id));
  }
  return getOcrSettings();
}

// `category` and `note` (v1.5) are intentionally excluded here — both are
// user-set only, never guessed by OCR. Do not add them to this schema.
const RECEIPT_FIELDS_SCHEMA = {
  type: 'object',
  properties: {
    date: { type: 'string', description: 'Receipt date in YYYY-MM-DD format' },
    merchant: { type: 'string', description: 'Merchant or vendor name' },
    total_cost: { type: 'number', description: 'Total amount charged, in dollars' },
    description: { type: 'string', description: 'Brief description of the item(s) purchased' },
  },
  required: ['date', 'merchant', 'total_cost', 'description'],
  additionalProperties: false,
};

const RECEIPTS_SCHEMA = {
  type: 'object',
  properties: {
    receipts: { type: 'array', items: RECEIPT_FIELDS_SCHEMA },
  },
  required: ['receipts'],
  additionalProperties: false,
};

const EXTRACTION_PROMPT =
  'These images may contain one or more separate, distinct receipts (a multi-page receipt spans multiple images; unrelated receipts are separate). Identify EACH separate receipt and extract its date, merchant name, total cost, and a brief description of the item(s) purchased as its own entry. Do not merge multiple receipts into one entry. If there is only one receipt, return a single entry. Give your best reasonable guess for any field that is not perfectly clear.';

const MEDIA_TYPES = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
};

// THE entry point for receipt OCR, whichever provider is selected in
// Settings. Accepts either a single absolute image path (string) or an array
// of 1..N absolute paths (e.g. rendered pages of an imported PDF) — all sent
// as images in one request. Mirrors iOS's
// `ReceiptExtractor.extractReceipts(images:)` unification: ONE
// canonical function for both the single-photo and multi-page-PDF paths,
// not two parallel implementations. The prompt/schema are unchanged and
// already array-returning — the model decides whether the supplied pages
// are one receipt spanning multiple images or several separate receipts.
export async function extractReceiptFields(imageAbsolutePathOrPaths) {
  const imagePaths = Array.isArray(imageAbsolutePathOrPaths)
    ? imageAbsolutePathOrPaths
    : [imageAbsolutePathOrPaths];
  if (imagePaths.length === 0) {
    throw new Error('At least one image path is required for OCR extraction');
  }

  const images = imagePaths.map((imageAbsolutePath) => {
    const ext = path.extname(imageAbsolutePath).toLowerCase();
    const mediaType = MEDIA_TYPES[ext];
    if (!mediaType) {
      throw new Error(`Unsupported image type for OCR: ${ext}`);
    }
    return { mediaType, base64: fs.readFileSync(imageAbsolutePath).toString('base64') };
  });

  const { provider, providers } = getOcrSettings();
  const selected = providers[provider];
  if (!selected.configured) {
    throw new Error(`No ${selected.displayName} API key configured — set ${selected.envVar} in backend/.env`);
  }

  const text = await OCR_PROVIDERS[provider].adapter.extractJsonText({
    images,
    prompt: EXTRACTION_PROMPT,
    schema: RECEIPTS_SCHEMA,
    model: selected.model || selected.defaultModel,
  });
  if (!text) {
    throw new Error('OCR extraction returned no text content');
  }

  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error('OCR extraction returned invalid JSON');
  }

  if (!Array.isArray(parsed.receipts)) {
    throw new Error('OCR extraction returned an unexpected shape');
  }

  return parsed.receipts;
}
