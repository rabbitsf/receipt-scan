// Google Gemini wire format only (Interactions API with a JSON-schema
// `response_format`; generateContent is now labelled legacy), via plain
// fetch — no SDK dependency. `store: false` keeps each scan stateless.
// Mirrors iOS's `GeminiVisionClient.swift`. Returns the model's raw JSON text.
export async function extractJsonText({ images, prompt, schema, model }) {
  const res = await fetch('https://generativelanguage.googleapis.com/v1beta/interactions', {
    method: 'POST',
    headers: {
      'x-goog-api-key': process.env.GEMINI_API_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      store: false,
      input: [
        ...images.map(({ mediaType, base64 }) => ({ type: 'image', data: base64, mime_type: mediaType })),
        { type: 'text', text: prompt },
      ],
      response_format: { type: 'text', mime_type: 'application/json', schema },
    }),
  });

  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(body.error?.message || `Gemini request failed with status ${res.status}`);
  }

  const part = (body.steps || [])
    .filter((step) => step.type === 'model_output')
    .flatMap((step) => step.content || [])
    .find((c) => c.type === 'text');
  return part?.text ?? null;
}
