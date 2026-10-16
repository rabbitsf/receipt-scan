// OpenAI wire format only (Responses API + strict Structured Outputs), via
// plain fetch — no SDK dependency. Mirrors iOS's `OpenAIVisionClient.swift`.
// Returns the model's raw JSON text.
export async function extractJsonText({ images, prompt, schema, model }) {
  const res = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      input: [
        {
          role: 'user',
          content: [
            ...images.map(({ mediaType, base64 }) => ({
              type: 'input_image',
              image_url: `data:${mediaType};base64,${base64}`,
            })),
            { type: 'input_text', text: prompt },
          ],
        },
      ],
      text: { format: { type: 'json_schema', name: 'receipts', schema, strict: true } },
    }),
  });

  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(body.error?.message || `OpenAI request failed with status ${res.status}`);
  }

  // Reasoning models emit a `reasoning` item before the `message` item.
  const part = (body.output || [])
    .filter((item) => item.type === 'message')
    .flatMap((item) => item.content || [])
    .find((c) => c.type === 'output_text');
  return part?.text ?? null;
}
