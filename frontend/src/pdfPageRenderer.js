import * as pdfjsLib from 'pdfjs-dist';
import pdfjsWorker from 'pdfjs-dist/build/pdf.worker.min.mjs?url';

pdfjsLib.GlobalWorkerOptions.workerSrc = pdfjsWorker;

// Renders PDF pages to JPEG Blobs so they flow through the same OCR/upload
// pipeline as a photo. How many pages, and at what size/quality, is decided
// by `pdfScanBudget.js`; this file only draws. Mirrors iOS's `PDFPageRenderer`.

// The "Scan first N pages" choice in the PDF cost popup (iOS: `quickScanPages`).
export const QUICK_SCAN_PAGES = 5;

export async function loadPdf(file) {
  return pdfjsLib.getDocument({ data: await file.arrayBuffer() }).promise;
}

function scaleFor(page, maxEdge) {
  const base = page.getViewport({ scale: 1 });
  return maxEdge / Math.max(base.width, base.height);
}

// Pixel size of pages 1..count at `maxEdge` — for cost estimates, no drawing.
export async function renderedSizes(pdf, count, maxEdge) {
  const sizes = [];
  for (let n = 1; n <= count; n++) {
    const page = await pdf.getPage(n);
    const viewport = page.getViewport({ scale: scaleFor(page, maxEdge) });
    sizes.push({ width: Math.round(viewport.width), height: Math.round(viewport.height) });
  }
  return sizes;
}

// JPEG Blob of one page (1-based).
export async function renderPage(pdf, pageNumber, maxEdge, quality) {
  const page = await pdf.getPage(pageNumber);
  const viewport = page.getViewport({ scale: scaleFor(page, maxEdge) });
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(viewport.width);
  canvas.height = Math.round(viewport.height);
  const context = canvas.getContext('2d');
  context.fillStyle = '#fff';
  context.fillRect(0, 0, canvas.width, canvas.height);
  await page.render({ canvasContext: context, viewport }).promise;
  return new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
}

// JPEG Blobs of pages 1..count.
export async function renderPages(pdf, count, maxEdge, quality) {
  const blobs = [];
  for (let n = 1; n <= count; n++) {
    const blob = await renderPage(pdf, n, maxEdge, quality);
    if (blob) blobs.push(blob);
  }
  return blobs;
}
