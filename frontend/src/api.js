const BASE = '/api/receipts';

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

export async function extractReceiptFields(imagePath) {
  const res = await fetch(`${BASE}/extract`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ imagePath }),
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
