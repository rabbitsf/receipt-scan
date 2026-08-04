import * as pdfjsLib from 'pdfjs-dist';
import pdfjsWorker from 'pdfjs-dist/build/pdf.worker.min.mjs?url';

pdfjsLib.GlobalWorkerOptions.workerSrc = pdfjsWorker;

// Page cap, mirrors iOS's `PDFPageRenderer.maxPages` — keeps an unusually
// long PDF from blowing up OCR request cost/latency. Single source of
// truth for the warning shown before scanning (see `UploadReceipt.jsx`).
export const MAX_PAGES = 5;

// Longest-edge cap in pixels, same spirit as the JPEG compression already
// used for camera/library photo uploads — good enough for OCR without an
// oversized upload.
const MAX_DIMENSION = 2200;

// Renders each page of a PDF (up to MAX_PAGES) to a JPEG Blob, so it can
// flow through the same OCR/upload pipeline as a camera/library photo —
// there is no PDF/document upload path, only images.
export async function renderPdfPages(file) {
  const arrayBuffer = await file.arrayBuffer();
  const pdf = await pdfjsLib.getDocument({ data: arrayBuffer }).promise;
  const pageCount = Math.min(pdf.numPages, MAX_PAGES);

  const blobs = [];
  for (let pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
    const page = await pdf.getPage(pageNumber);
    const baseViewport = page.getViewport({ scale: 1 });
    const scale = MAX_DIMENSION / Math.max(baseViewport.width, baseViewport.height);
    const viewport = page.getViewport({ scale });

    const canvas = document.createElement('canvas');
    canvas.width = Math.round(viewport.width);
    canvas.height = Math.round(viewport.height);
    const context = canvas.getContext('2d');
    await page.render({ canvasContext: context, viewport }).promise;

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.8));
    if (blob) blobs.push(blob);
  }

  return blobs;
}
