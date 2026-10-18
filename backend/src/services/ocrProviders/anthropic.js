import { labeledContent, MAX_OUTPUT_TOKENS } from './labeledContent.js';
import Anthropic from '@anthropic-ai/sdk';

let client;
function getClient() {
  if (!client) {
    client = new Anthropic();
  }
  return client;
}

// Anthropic wire format only — prompt/schema/parsing are shared in
// `ocrService.js`. Returns the model's raw JSON text.
export async function extractJsonText({ images, prompt, schema, model }) {
  const response = await getClient().messages.create({
    model,
    max_tokens: MAX_OUTPUT_TOKENS,
    output_config: { format: { type: 'json_schema', schema } },
    messages: [
      {
        role: 'user',
        content: labeledContent(images, prompt, {
          text: (t) => ({ type: 'text', text: t }),
          image: ({ mediaType, base64 }) => ({
            type: 'image',
            source: { type: 'base64', media_type: mediaType, data: base64 },
          }),
        }),
      },
    ],
  });

  return response.content.find((block) => block.type === 'text')?.text ?? null;
}
