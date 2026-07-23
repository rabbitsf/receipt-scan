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

export async function extractReceiptFields(imageAbsolutePath) {
  const ext = path.extname(imageAbsolutePath).toLowerCase();
  const mediaType = MEDIA_TYPES[ext];
  if (!mediaType) {
    throw new Error(`Unsupported image type for OCR: ${ext}`);
  }

  const imageBase64 = fs.readFileSync(imageAbsolutePath).toString('base64');

  const response = await getClient().messages.create({
    model: 'claude-opus-4-8',
    max_tokens: 4096,
    output_config: { format: { type: 'json_schema', schema: RECEIPTS_SCHEMA } },
    messages: [
      {
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageBase64 } },
          {
            type: 'text',
            text: 'This photo may contain one or more separate, distinct receipts. Identify EACH separate receipt in the image and extract its date, merchant name, total cost, and a brief description of the item(s) purchased as its own entry. Do not merge multiple receipts into one entry. If there is only one receipt, return a single entry. Give your best reasonable guess for any field that is not perfectly clear.',
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
