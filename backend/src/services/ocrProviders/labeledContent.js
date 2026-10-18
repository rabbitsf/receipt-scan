// Shared by the three provider adapters: an "Image N:" text label before each
// image (Anthropic's recommended multi-image layout), then the prompt — so the
// model's `pages` numbers refer to these labels. Each adapter supplies how to
// build its own text and image blocks. Mirrors iOS's
// `ReceiptExtraction.labeledContent`.
export function labeledContent(images, prompt, { text, image }) {
  const blocks = [];
  images.forEach((img, index) => {
    blocks.push(text(`Image ${index + 1}:`));
    blocks.push(image(img));
  });
  blocks.push(text(prompt));
  return blocks;
}

// Most output tokens a scan may produce (many receipts in a long PDF need
// room). Mirrors iOS's `ReceiptExtraction.maxOutputTokens`.
export const MAX_OUTPUT_TOKENS = 16000;
