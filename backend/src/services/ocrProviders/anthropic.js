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
    max_tokens: 4096,
    output_config: { format: { type: 'json_schema', schema } },
    messages: [
      {
        role: 'user',
        content: [
          ...images.map(({ mediaType, base64 }) => ({
            type: 'image',
            source: { type: 'base64', media_type: mediaType, data: base64 },
          })),
          { type: 'text', text: prompt },
        ],
      },
    ],
  });

  return response.content.find((block) => block.type === 'text')?.text ?? null;
}
