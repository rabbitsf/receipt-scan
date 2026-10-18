import express, { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import multer from 'multer';
import { v4 as uuidv4 } from 'uuid';
import {
  listReceipts,
  getReceiptById,
  getReceiptsByIds,
  createReceipt,
  updateReceipt,
  deleteReceipt,
  getYearSummary,
  countReceiptsByImagePath,
  countReceiptsByPdfPath,
  getDistinctCategories,
  getDistinctGroups,
} from '../services/receiptsRepository.js';
import { extractReceiptFields, getOcrSettings, OCR_PROVIDERS } from '../services/ocrService.js';
import { PROVIDER_LIMITS, estimateScanCost } from '../services/ocrScanCost.js';
import { generateReceiptsPdf, generateReceiptsExcel } from '../services/exportService.js';
import { dataDir, uploadsDir } from '../utils/paths.js';
import {
  listCustomValues,
  createCustomValue,
  renameCustomValue,
  deleteCustomValueIfUnused,
} from '../services/customValuesRepository.js';

const router = Router();
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const ALLOWED_IMAGE_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
]);

// Images (receipt photos, rendered PDF pages) and PDFs (a receipt's own
// pages from a PDF import, built in the browser).
const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, uploadsDir),
    filename: (req, file, cb) =>
      cb(null, `${uuidv4()}${file.mimetype === 'application/pdf' ? '.pdf' : path.extname(file.originalname).toLowerCase()}`),
  }),
  limits: { fileSize: 50 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_IMAGE_MIME_TYPES.has(file.mimetype) && file.mimetype !== 'application/pdf') {
      cb(new Error('Only JPEG, PNG, WEBP, HEIC/HEIF images or PDFs are allowed'));
      return;
    }
    cb(null, true);
  },
});

function validateReceiptInput(body, { partial = false } = {}) {
  const errors = [];
  const result = {};

  if (!partial || body.date !== undefined) {
    if (typeof body.date !== 'string' || !DATE_RE.test(body.date) || Number.isNaN(Date.parse(body.date))) {
      errors.push('date must be a valid YYYY-MM-DD string');
    } else {
      result.date = body.date;
    }
  }

  if (!partial || body.totalCost !== undefined) {
    const totalCost = Number(body.totalCost);
    if (!Number.isFinite(totalCost) || totalCost < 0) {
      errors.push('totalCost must be a non-negative number');
    } else {
      result.totalCost = totalCost;
    }
  }

  if (body.merchant !== undefined) {
    result.merchant = body.merchant === null ? null : String(body.merchant).trim();
  }
  if (body.description !== undefined) {
    result.description = body.description === null ? null : String(body.description).trim();
  }
  if (body.category !== undefined) {
    result.category = body.category === null ? null : String(body.category).trim();
  }
  if (body.group !== undefined) {
    result.group = body.group === null ? null : String(body.group).trim();
  }
  if (body.note !== undefined) {
    result.note = body.note === null ? null : String(body.note).trim();
  }
  if (body.imagePath !== undefined) {
    result.imagePath = body.imagePath;
  }
  if (body.pdfPath !== undefined) {
    if (body.pdfPath !== null && !(typeof body.pdfPath === 'string' && /^uploads\/[\w-]+\.pdf$/.test(body.pdfPath))) {
      errors.push('pdfPath must be null or an uploaded PDF path');
    } else {
      result.pdfPath = body.pdfPath;
    }
  }

  return { errors, result };
}

function validateFilterParams(query) {
  const { year, month, q, category, group } = query;
  const errors = [];

  if (year !== undefined && !/^\d{4}$/.test(year)) {
    errors.push('year must be a 4-digit number');
  }
  if (month !== undefined) {
    const monthNum = Number(month);
    if (!Number.isInteger(monthNum) || monthNum < 1 || monthNum > 12) {
      errors.push('month must be an integer between 1 and 12');
    }
  }

  return { errors, filters: { year, month, q, category, group } };
}

function buildExportFilename(filters, format) {
  const parts = ['receipts'];
  if (filters.year) parts.push(filters.year);
  if (filters.month) parts.push(String(filters.month).padStart(2, '0'));
  if (filters.category) parts.push('category');
  if (filters.group) parts.push('group');
  if (filters.q) parts.push('search');
  return `${parts.join('-')}.${format}`;
}

// Deletes a receipt row and, if no sibling row still references the same
// image_path / pdf_path (multi-receipt-per-photo), removes those files.
function deleteReceiptAndMaybeImage(id) {
  const deleted = deleteReceipt(id);
  if (!deleted) return null;

  const unlinkIfUnused = (relPath, count) => {
    if (!relPath || count(relPath) !== 0) return;
    const absPath = path.join(dataDir, relPath);
    fs.unlink(absPath, (err) => {
      if (err && err.code !== 'ENOENT') {
        console.error('Failed to delete receipt file:', absPath, err);
      }
    });
  };
  unlinkIfUnused(deleted.imagePath, countReceiptsByImagePath);
  unlinkIfUnused(deleted.pdfPath, countReceiptsByPdfPath);

  return deleted;
}

router.get('/', (req, res) => {
  const { errors, filters } = validateFilterParams(req.query);
  if (errors.length) return res.status(400).json({ errors });
  res.json(listReceipts(filters));
});

router.post('/', (req, res) => {
  const { errors, result } = validateReceiptInput(req.body);
  if (errors.length) return res.status(400).json({ errors });
  res.status(201).json(createReceipt(result));
});

// Registered before '/:id' so these fixed paths aren't shadowed by the param route.
router.post('/upload', (req, res) => {
  upload.single('image')(req, res, (err) => {
    if (err) {
      const message = err instanceof multer.MulterError ? err.message : err.message || 'Upload failed';
      return res.status(400).json({ error: message });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'No image file provided (field name: image)' });
    }
    const key = req.file.mimetype === 'application/pdf' ? 'pdfPath' : 'imagePath';
    res.status(201).json({ [key]: `uploads/${req.file.filename}` });
  });
});

router.use('/images', express.static(uploadsDir));

// Page count, estimated cost and request limits for scanning images of the
// given sizes with the selected provider — feeds the PDF import cost popup
// and page budget (`frontend/src/pdfImport.js`). `usd` is null for a custom model.
router.post('/extract/estimate', (req, res) => {
  const { pageSizes } = req.body || {};
  if (!Array.isArray(pageSizes) || !pageSizes.every((p) => p && Number(p.width) > 0 && Number(p.height) > 0)) {
    return res.status(400).json({ error: 'pageSizes must be an array of { width, height }' });
  }
  const { provider, providers } = getOcrSettings();
  const selected = providers[provider];
  const model = selected.model || selected.defaultModel;
  const estimate = estimateScanCost({
    pageSizes: pageSizes.map((p) => ({ width: Number(p.width), height: Number(p.height) })),
    provider,
    isDefaultModel: model === OCR_PROVIDERS[provider].defaultModel,
  });
  res.json({ ...estimate, provider, providerName: selected.displayName, model, limits: PROVIDER_LIMITS[provider] });
});

router.post('/extract', async (req, res) => {
  const { imagePath, imagePaths } = req.body;
  const paths = Array.isArray(imagePaths) ? imagePaths : imagePath !== undefined ? [imagePath] : [];

  if (paths.length === 0 || !paths.every((p) => typeof p === 'string' && p)) {
    return res.status(400).json({ error: 'imagePath or a non-empty imagePaths array of strings is required' });
  }
  // The selected provider's own per-request image limit.
  const maxImages = PROVIDER_LIMITS[getOcrSettings().provider].maxImagesPerRequest;
  if (paths.length > maxImages) {
    return res.status(400).json({ error: `imagePaths cannot contain more than ${maxImages} images` });
  }

  const resolvedDataDir = path.resolve(dataDir);
  const absPaths = [];
  for (const p of paths) {
    const absPath = path.resolve(dataDir, p);
    if (!absPath.startsWith(resolvedDataDir + path.sep)) {
      return res.status(400).json({ error: 'Invalid imagePath' });
    }
    if (!fs.existsSync(absPath)) {
      return res.status(404).json({ error: 'Image not found' });
    }
    absPaths.push(absPath);
  }

  try {
    const extracted = await extractReceiptFields(absPaths);
    res.json(extracted);
  } catch (err) {
    console.error('OCR extraction failed:', err);
    res.status(502).json({ error: 'OCR extraction failed', detail: err.message });
  }
});

router.post('/bulk-delete', (req, res) => {
  const { ids } = req.body;
  if (!Array.isArray(ids) || ids.length === 0 || !ids.every((id) => Number.isInteger(id))) {
    return res.status(400).json({ error: 'ids must be a non-empty array of integers' });
  }

  const deleted = [];
  const notFound = [];
  for (const id of ids) {
    const result = deleteReceiptAndMaybeImage(id);
    if (result) {
      deleted.push(id);
    } else {
      notFound.push(id);
    }
  }

  res.json({ deleted, notFound });
});

router.get('/export', async (req, res) => {
  const { format, ids } = req.query;
  if (format !== 'pdf' && format !== 'xlsx') {
    return res.status(400).json({ error: "format must be 'pdf' or 'xlsx'" });
  }

  let receipts;
  let filename;

  if (ids !== undefined) {
    const idList = String(ids)
      .split(',')
      .map((s) => Number(s.trim()))
      .filter((n) => Number.isInteger(n));
    if (idList.length === 0) {
      return res.status(400).json({ error: 'ids must be a comma-separated list of integers' });
    }
    receipts = getReceiptsByIds(idList);
    filename = `receipts-selected.${format}`;
  } else {
    const { errors, filters } = validateFilterParams(req.query);
    if (errors.length) return res.status(400).json({ errors });
    receipts = listReceipts(filters);
    filename = buildExportFilename(filters, format);
  }

  try {
    if (format === 'pdf') {
      const buffer = await generateReceiptsPdf(receipts);
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
      return res.send(buffer);
    }

    const buffer = await generateReceiptsExcel(receipts);
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.send(Buffer.from(buffer));
  } catch (err) {
    console.error('Export failed:', err);
    res.status(500).json({ error: 'Export failed' });
  }
});

router.get('/summary', (req, res) => {
  const { year } = req.query;
  if (!year || !/^\d{4}$/.test(year)) {
    return res.status(400).json({ error: 'year must be a 4-digit number' });
  }
  res.json(getYearSummary(year));
});

// Union of in-use values and Settings-created (possibly zero-usage)
// `custom_values` entries, deduplicated and sorted — so a Settings-created
// category/group appears in pickers before any receipt uses it. Mirrors
// iOS's `CategoryOptions.mergeWithInUseCategories(_:customCategories:)`.
function mergedDistinctValues(kind, inUse) {
  const custom = listCustomValues(kind).map((v) => v.name);
  return Array.from(new Set([...inUse, ...custom])).sort();
}

// Registered before '/:id' so these fixed paths aren't shadowed by the param route.
router.get('/categories', (req, res) => {
  res.json(mergedDistinctValues('category', getDistinctCategories()));
});

router.post('/categories', (req, res) => {
  const created = createCustomValue('category', req.body.name);
  if (!created) return res.status(400).json({ error: 'name is required' });
  res.status(201).json(created);
});

router.put('/categories/:name', (req, res) => {
  const renamed = renameCustomValue('category', req.params.name, req.body.name);
  if (!renamed) return res.status(400).json({ error: 'name is required and must differ from the current name' });
  res.json(renamed);
});

router.delete('/categories/:name', (req, res) => {
  const result = deleteCustomValueIfUnused('category', req.params.name);
  if (!result.deleted) {
    return res
      .status(409)
      .json({ error: `Still used by ${result.count} receipt${result.count === 1 ? '' : 's'}`, count: result.count });
  }
  res.status(204).end();
});

router.get('/groups', (req, res) => {
  res.json(mergedDistinctValues('group', getDistinctGroups()));
});

router.post('/groups', (req, res) => {
  const created = createCustomValue('group', req.body.name);
  if (!created) return res.status(400).json({ error: 'name is required' });
  res.status(201).json(created);
});

router.put('/groups/:name', (req, res) => {
  const renamed = renameCustomValue('group', req.params.name, req.body.name);
  if (!renamed) return res.status(400).json({ error: 'name is required and must differ from the current name' });
  res.json(renamed);
});

router.delete('/groups/:name', (req, res) => {
  const result = deleteCustomValueIfUnused('group', req.params.name);
  if (!result.deleted) {
    return res
      .status(409)
      .json({ error: `Still used by ${result.count} receipt${result.count === 1 ? '' : 's'}`, count: result.count });
  }
  res.status(204).end();
});

router.get('/:id', (req, res) => {
  const receipt = getReceiptById(Number(req.params.id));
  if (!receipt) return res.status(404).json({ error: 'Receipt not found' });
  res.json(receipt);
});

router.put('/:id', (req, res) => {
  const id = Number(req.params.id);
  const existing = getReceiptById(id);
  if (!existing) return res.status(404).json({ error: 'Receipt not found' });

  const { errors, result } = validateReceiptInput(req.body, { partial: true });
  if (errors.length) return res.status(400).json({ errors });

  const merged = {
    date: result.date ?? existing.date,
    totalCost: result.totalCost ?? existing.totalCost,
    merchant: result.merchant !== undefined ? result.merchant : existing.merchant,
    description: result.description !== undefined ? result.description : existing.description,
    category: result.category !== undefined ? result.category : existing.category,
    group: result.group !== undefined ? result.group : existing.group,
    note: result.note !== undefined ? result.note : existing.note,
    imagePath: result.imagePath !== undefined ? result.imagePath : existing.imagePath,
    pdfPath: result.pdfPath, // undefined keeps the current PDF; null removes it
  };

  res.json(updateReceipt(id, merged));
});

router.delete('/:id', (req, res) => {
  const deleted = deleteReceiptAndMaybeImage(Number(req.params.id));
  if (!deleted) return res.status(404).json({ error: 'Receipt not found' });
  res.status(204).end();
});

export default router;
