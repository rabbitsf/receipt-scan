// How a PDF's pages are sent for scanning (shrink, then split into parts) and
// which pages each receipt keeps. Mirrors iOS's `PDFScanBudget.swift`
// (PDFScanBudget / PDFPageAssignment) — change both together.

// Above this many pages Claude needs every image ≤ 2000 px, so all providers
// render a little smaller (one simple rule).
export const MANY_PAGES_THRESHOLD = 20;

// Tried in order; the last one is the readable floor.
export function budgetSteps(pageCount) {
  return [
    { maxEdge: pageCount > MANY_PAGES_THRESHOLD ? 2000 : 2200, quality: 0.8 },
    { maxEdge: 1600, quality: 0.7 },
    { maxEdge: 1300, quality: 0.6 },
  ];
}

const REQUEST_OVERHEAD_BYTES = 64 * 1024;
const PER_IMAGE_OVERHEAD_BYTES = 256;
const SAFETY_FACTOR = 0.9;
const base64Length = (bytes) => Math.ceil(bytes / 3) * 4;

export function requestBytes(byteCounts) {
  return REQUEST_OVERHEAD_BYTES + byteCounts.reduce((sum, n) => sum + base64Length(n) + PER_IMAGE_OVERHEAD_BYTES, 0);
}

// `limits` = { maxImagesPerRequest, maxRequestBytes } of the selected provider.
export function fitsInOneRequest(byteCounts, limits) {
  return byteCounts.length <= limits.maxImagesPerRequest && requestBytes(byteCounts) <= limits.maxRequestBytes * SAFETY_FACTOR;
}

// Consecutive [start, end) index ranges, each small enough for one request.
export function splitIntoParts(byteCounts, limits) {
  const parts = [];
  let start = 0;
  while (start < byteCounts.length) {
    let end = start + 1;
    while (end < byteCounts.length && fitsInOneRequest(byteCounts.slice(start, end + 1), limits)) end += 1;
    parts.push([start, end]);
    start = end;
  }
  return parts;
}

// A part's own "Image N" numbers (1-based) → file page positions.
export function filePages(partPages, [start, end]) {
  return (partPages || []).filter((n) => Number.isInteger(n) && n >= 1 && n <= end - start).map((n) => start + n);
}

// Which pages (1-based file positions) each receipt keeps:
// - one receipt keeps every page (even unscanned ones);
// - several receipts keep their valid listed pages, sorted and unique;
// - a receipt with no usable pages keeps the whole file;
// `unkeptPages` lists unscanned pages no receipt keeps.
export function assignPages(receiptPages, scannedPageCount, totalPageCount) {
  const allPages = Array.from({ length: totalPageCount }, (_, i) => i + 1);
  if (receiptPages.length <= 1) {
    return { pagesPerReceipt: receiptPages.map(() => allPages), unkeptPages: [] };
  }
  const perReceipt = receiptPages.map((reported) => {
    const valid = [...new Set((reported || []).filter((n) => n >= 1 && n <= Math.max(scannedPageCount, 1) && n <= totalPageCount))].sort(
      (a, b) => a - b,
    );
    return valid.length ? valid : allPages;
  });
  const kept = new Set(perReceipt.flat());
  return { pagesPerReceipt: perReceipt, unkeptPages: allPages.filter((n) => !kept.has(n) && n > scannedPageCount) };
}

// "page 2", "pages 1–3", "pages 1, 3".
export function pagesLabel(pages) {
  if (!pages.length) return '';
  if (pages.length === 1) return `page ${pages[0]}`;
  const contiguous = pages.every((n, i) => i === 0 || n === pages[i - 1] + 1);
  return contiguous ? `pages ${pages[0]}–${pages[pages.length - 1]}` : `pages ${pages.join(', ')}`;
}
