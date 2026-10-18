const BASE = '/api/receipts';

// URL of a stored photo or PDF (`uploads/<file>`), served by both servers.
export function fileUrl(path) {
  return path ? `${BASE}/images/${path.replace(/^uploads\//, '')}` : null;
}

async function parseErrorResponse(res, fallback) {
  const body = await res.json().catch(() => ({}));
  if (Array.isArray(body.errors) && body.errors.length) return body.errors.join(', ');
  return body.error || fallback;
}

export async function uploadReceiptImage(file) {
  const formData = new FormData();
  formData.append('image', file);

  const res = await fetch(`${BASE}/upload`, { method: 'POST', body: formData });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Upload failed'));
  return res.json();
}

// A receipt's own pages from a PDF import (built in the browser). Returns { pdfPath }.
export async function uploadReceiptPdf(blob, filename = 'receipt.pdf') {
  const formData = new FormData();
  formData.append('image', new File([blob], filename, { type: 'application/pdf' }));
  const res = await fetch(`${BASE}/upload`, { method: 'POST', body: formData });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Upload failed'));
  return res.json();
}

// Estimated cost and the selected provider's request limits for scanning
// images of these sizes: { inputTokens, outputTokens, usd|null, providerName, model, limits }.
export async function estimateScan(pageSizes) {
  const res = await fetch(`${BASE}/extract/estimate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ pageSizes }),
  });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to estimate scan cost'));
  return res.json();
}

// Accepts either a single imagePath (string) or multiple (array) — e.g. all
// rendered pages of an imported PDF sent together so the model can decide
// whether they're one receipt or several.
export async function extractReceiptFields(imagePathOrPaths) {
  const body = Array.isArray(imagePathOrPaths)
    ? { imagePaths: imagePathOrPaths }
    : { imagePath: imagePathOrPaths };
  const res = await fetch(`${BASE}/extract`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Extraction failed'));
  return res.json();
}

export async function createReceipt(fields) {
  const res = await fetch(BASE, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(fields),
  });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Save failed'));
  return res.json();
}

export async function listReceipts(filters = {}) {
  const params = new URLSearchParams();
  if (filters.year) params.set('year', filters.year);
  if (filters.month) params.set('month', filters.month);
  if (filters.q) params.set('q', filters.q);
  if (filters.category) params.set('category', filters.category);
  if (filters.group) params.set('group', filters.group);

  const qs = params.toString();
  const res = await fetch(qs ? `${BASE}?${qs}` : BASE);
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to load receipts'));
  return res.json();
}

export async function getReceipt(id) {
  const res = await fetch(`${BASE}/${id}`);
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to load receipt'));
  return res.json();
}

export async function updateReceipt(id, fields) {
  const res = await fetch(`${BASE}/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(fields),
  });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Save failed'));
  return res.json();
}

export async function deleteReceipt(id) {
  const res = await fetch(`${BASE}/${id}`, { method: 'DELETE' });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Delete failed'));
}

export async function bulkDeleteReceipts(ids) {
  const res = await fetch(`${BASE}/bulk-delete`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ids }),
  });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Bulk delete failed'));
  return res.json();
}

export async function getYearSummary(year) {
  const res = await fetch(`${BASE}/summary?year=${year}`);
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to load summary'));
  return res.json();
}

export async function getCategories() {
  const res = await fetch(`${BASE}/categories`);
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to load categories'));
  return res.json();
}

export async function createCategory(name) {
  const res = await fetch(`${BASE}/categories`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name }),
  });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to add category'));
  return res.json();
}

export async function renameCategory(name, newName) {
  const res = await fetch(`${BASE}/categories/${encodeURIComponent(name)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: newName }),
  });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to rename category'));
  return res.json();
}

export async function deleteCategory(name) {
  const res = await fetch(`${BASE}/categories/${encodeURIComponent(name)}`, { method: 'DELETE' });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const err = new Error(body.error || 'Failed to delete category');
    err.count = body.count;
    throw err;
  }
}

export async function getGroups() {
  const res = await fetch(`${BASE}/groups`);
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to load groups'));
  return res.json();
}

export async function createGroup(name) {
  const res = await fetch(`${BASE}/groups`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name }),
  });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to add group'));
  return res.json();
}

export async function renameGroup(name, newName) {
  const res = await fetch(`${BASE}/groups/${encodeURIComponent(name)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: newName }),
  });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to rename group'));
  return res.json();
}

export async function deleteGroup(name) {
  const res = await fetch(`${BASE}/groups/${encodeURIComponent(name)}`, { method: 'DELETE' });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const err = new Error(body.error || 'Failed to delete group');
    err.count = body.count;
    throw err;
  }
}

// OCR provider/model preference (Settings → Receipt Scanning). API keys
// stay in backend env vars — the response only says whether each is set.
export async function getOcrSettings() {
  const res = await fetch('/api/settings/ocr');
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to load scanning settings'));
  return res.json();
}

export async function updateOcrSettings(changes) {
  const res = await fetch('/api/settings/ocr', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(changes),
  });
  if (!res.ok) throw new Error(await parseErrorResponse(res, 'Failed to save scanning settings'));
  return res.json();
}
