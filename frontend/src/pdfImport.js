import { PDFDocument } from 'pdf-lib';
import { uploadReceiptImage, uploadReceiptPdf, extractReceiptFields, estimateScan } from './api.js';
import { loadPdf, renderedSizes, renderPages, renderPage, QUICK_SCAN_PAGES } from './pdfPageRenderer.js';
import { budgetSteps, fitsInOneRequest, splitIntoParts, filePages, assignPages, pagesLabel } from './pdfScanBudget.js';
import { emptyReceiptValues, toFormValues } from './receiptFields.js';

// THE PDF import pipeline (web): several files, each scanned on its own,
// shrunk/split per `pdfScanBudget.js`, pages matched to receipts, each receipt
// given its own PDF (built here with pdf-lib) and first-page photo.
// Mirrors iOS's `PDFImportScanner.swift`.
//
// A review item: { values, imagePath, pdfPath, sourceLabel, notices }.

// "~$0.12", "under $0.01", or "cost unknown" (custom model). Same wording as
// iOS's `OCRScanCost.formatted`.
export function formatUsd(usd) {
  if (usd == null) return 'cost unknown';
  return usd < 0.01 ? 'under $0.01' : `~$${usd.toFixed(2)}`;
}

// Page counts and estimated cost for the cost popup (no rendering).
// `allPagesUsd`/`quickScanUsd` are null when a custom model is set.
export async function costSummary(files) {
  const summary = { files: [], totalPages: 0, quickScanPages: 0, allPagesUsd: 0, quickScanUsd: 0, providerName: '', model: '' };
  const addUsd = (key, estimate) => {
    summary[key] = estimate.usd == null || summary[key] == null ? null : summary[key] + estimate.usd;
  };
  for (const file of files) {
    let pdf;
    try {
      pdf = await loadPdf(file);
    } catch {
      summary.files.push({ name: file.name, pages: 0 });
      continue;
    }
    const total = pdf.numPages;
    const quick = Math.min(total, QUICK_SCAN_PAGES);
    summary.files.push({ name: file.name, pages: total });
    summary.totalPages += total;
    summary.quickScanPages += quick;
    const all = await estimateScan(await renderedSizes(pdf, total, budgetSteps(total)[0].maxEdge));
    const first = await estimateScan(await renderedSizes(pdf, quick, budgetSteps(quick)[0].maxEdge));
    addUsd('allPagesUsd', all);
    addUsd('quickScanUsd', first);
    summary.providerName = all.providerName;
    summary.model = all.model;
    summary.limits = all.limits;
  }
  return summary;
}

// Scans every file in order (`onProgress(fileNumber, fileCount)`). Never
// throws: a file that can't be read or scanned becomes one blank entry with
// its whole PDF attached and a notice. `quickScan` scans only the first
// QUICK_SCAN_PAGES pages of each file.
export async function scanFiles(files, { quickScan, limits }, onProgress = () => {}) {
  const items = [];
  for (const [index, file] of files.entries()) {
    onProgress(index + 1, files.length);
    try {
      items.push(...(await scanFile(file, quickScan, limits)));
    } catch (err) {
      items.push(await blankItem(file, null, [`Scanning ${file.name} failed (${err.message}) — please check the fields.`]));
    }
  }
  return items;
}

async function scanFile(file, quickScan, limits) {
  let pdf;
  try {
    pdf = await loadPdf(file);
  } catch {
    return [await blankItem(file, null, [`Couldn't read ${file.name} — please enter this receipt by hand.`])];
  }
  const total = pdf.numPages;
  const scanned = quickScan ? Math.min(total, QUICK_SCAN_PAGES) : total;

  // Shrink, then split.
  let blobs = [];
  let parts = null;
  let shrunk = false;
  for (const [stepIndex, step] of budgetSteps(scanned).entries()) {
    blobs = await renderPages(pdf, scanned, step.maxEdge, step.quality);
    shrunk = stepIndex > 0;
    if (fitsInOneRequest(blobs.map((b) => b.size), limits)) {
      parts = [[0, blobs.length]];
      break;
    }
  }
  if (!parts) parts = splitIntoParts(blobs.map((b) => b.size), limits);

  const notices = [];
  if (parts.length > 1) {
    notices.push(
      `${file.name} was too large to scan at once, so it was scanned in ${parts.length} parts — a receipt that crosses parts may appear twice.`,
    );
  }

  const paths = [];
  for (const [i, blob] of blobs.entries()) {
    const { imagePath } = await uploadReceiptImage(new File([blob], `page-${i + 1}.jpg`, { type: 'image/jpeg' }));
    paths.push(imagePath);
  }

  let receipts = [];
  try {
    for (const part of parts) {
      const found = await extractReceiptFields(paths.slice(part[0], part[1]));
      receipts.push(...found.map((r) => ({ ...r, pages: filePages(r.pages, part) })));
    }
  } catch (err) {
    return [await blankItem(file, paths[0], [...notices, `Scanning ${file.name} failed (${err.message}) — please check the fields.`])];
  }
  if (receipts.length === 0) {
    return [await blankItem(file, paths[0], [...notices, `No receipt details were found in ${file.name} — please enter them by hand.`])];
  }

  const { pagesPerReceipt, unkeptPages } = assignPages(receipts.map((r) => r.pages), scanned, total);
  if (unkeptPages.length) {
    const first = unkeptPages[0];
    const last = unkeptPages[unkeptPages.length - 1];
    notices.push(`${first === last ? `Page ${first}` : `Pages ${first}–${last}`} of ${file.name} weren't scanned and aren't kept with these receipts.`);
  }

  const bytes = await file.arrayBuffer();
  const items = [];
  for (const [i, receipt] of receipts.entries()) {
    const pages = pagesPerReceipt[i];
    items.push({
      values: toFormValues(receipt),
      imagePath: await photoPath(pdf, pages[0], shrunk ? null : paths[pages[0] - 1]),
      pdfPath: (await uploadReceiptPdf(await subsetPdf(bytes, total, pages), file.name)).pdfPath,
      sourceLabel: `From ${file.name} · ${pagesLabel(pages)}`,
      notices,
    });
  }
  return items;
}

async function blankItem(file, imagePath, notices) {
  let pdfPath = null;
  try {
    ({ pdfPath } = await uploadReceiptPdf(file, file.name));
  } catch {
    // An unreadable file may also fail to upload; the entry still lets the user type the receipt.
  }
  return { values: emptyReceiptValues, imagePath: imagePath ?? null, pdfPath, sourceLabel: `From ${file.name}`, notices };
}

// The receipt's photo: its first page at normal photo quality (reuses the
// scanned image unless pages were shrunk to fit).
async function photoPath(pdf, pageNumber, existingPath) {
  if (existingPath) return existingPath;
  const blob = await renderPage(pdf, pageNumber, 2200, 0.8);
  return (await uploadReceiptImage(new File([blob], `page-${pageNumber}.jpg`, { type: 'image/jpeg' }))).imagePath;
}

// Just these pages (1-based), or the original file when it's every page.
async function subsetPdf(bytes, total, pages) {
  if (pages.length === total && pages.every((n, i) => n === i + 1)) return new Blob([bytes], { type: 'application/pdf' });
  const source = await PDFDocument.load(bytes, { ignoreEncryption: true });
  const subset = await PDFDocument.create();
  for (const page of await subset.copyPages(source, pages.map((n) => n - 1))) subset.addPage(page);
  return new Blob([await subset.save()], { type: 'application/pdf' });
}
