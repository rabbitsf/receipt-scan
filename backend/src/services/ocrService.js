import Anthropic from '@anthropic-ai/sdk';
import fs from 'node:fs';
import path from 'node:path';

let client;
function getClient() {
  if (!client) {
    client = new Anthropic();
  }
  return client;
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

const MEDIA_TYPES = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
};

// Accepts either a single absolute image path (string) or an array of 1..N
// absolute paths (e.g. rendered pages of an imported PDF) — one `image`
// content block per path, same request. Mirrors iOS's
// `AnthropicVisionClient.extractReceipts(images:)` unification: ONE
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

  const imageBlocks = imagePaths.map((imageAbsolutePath) => {
    const ext = path.extname(imageAbsolutePath).toLowerCase();
    const mediaType = MEDIA_TYPES[ext];
    if (!mediaType) {
      throw new Error(`Unsupported image type for OCR: ${ext}`);
    }
    const imageBase64 = fs.readFileSync(imageAbsolutePath).toString('base64');
    return { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageBase64 } };
  });

  const response = await getClient().messages.create({
    model: 'claude-opus-4-8',
    max_tokens: 4096,
    output_config: { format: { type: 'json_schema', schema: RECEIPTS_SCHEMA } },
    messages: [
      {
        role: 'user',
        content: [
          ...imageBlocks,
          {
            type: 'text',
            text: 'These images may contain one or more separate, distinct receipts (a multi-page receipt spans multiple images; unrelated receipts are separate). Identify EACH separate receipt and extract its date, merchant name, total cost, and a brief description of the item(s) purchased as its own entry. Do not merge multiple receipts into one entry. If there is only one receipt, return a single entry. Give your best reasonable guess for any field that is not perfectly clear.',
          },
        ],
      },
    ],
  });

  const textBlock = response.content.find((block) => block.type === 'text');
  if (!textBlock) {
    throw new Error('OCR extraction returned no text content');
  }

  let parsed;
  try {
    parsed = JSON.parse(textBlock.text);
  } catch {
    throw new Error('OCR extraction returned invalid JSON');
  }

  if (!Array.isArray(parsed.receipts)) {
    throw new Error('OCR extraction returned an unexpected shape');
  }

  return parsed.receipts;
}
