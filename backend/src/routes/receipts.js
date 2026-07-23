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
  getDistinctCategories,
} from '../services/receiptsRepository.js';
import { extractReceiptFields } from '../services/ocrService.js';
import { generateReceiptsPdf, generateReceiptsExcel } from '../services/exportService.js';
import { dataDir, uploadsDir } from '../utils/paths.js';

const router = Router();
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const ALLOWED_IMAGE_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
]);

const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, uploadsDir),
    filename: (req, file, cb) => cb(null, `${uuidv4()}${path.extname(file.originalname).toLowerCase()}`),
  }),
  limits: { fileSize: 15 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_IMAGE_MIME_TYPES.has(file.mimetype)) {
      cb(new Error('Only JPEG, PNG, WEBP, or HEIC/HEIF images are allowed'));
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
  if (body.note !== undefined) {
    result.note = body.note === null ? null : String(body.note).trim();
  }
  if (body.imagePath !== undefined) {
    result.imagePath = body.imagePath;
  }

  return { errors, result };
}

function validateFilterParams(query) {
  const { year, month, q, category } = query;
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

  return { errors, filters: { year, month, q, category } };
}

function buildExportFilename(filters, format) {
  const parts = ['receipts'];
  if (filters.year) parts.push(filters.year);
  if (filters.month) parts.push(String(filters.month).padStart(2, '0'));
  if (filters.category) parts.push('category');
  if (filters.q) parts.push('search');
  return `${parts.join('-')}.${format}`;
}

// Deletes a receipt row and, if no sibling row still references the same
// image_path (multi-receipt-per-photo), removes the underlying image file.
function deleteReceiptAndMaybeImage(id) {
  const deleted = deleteReceipt(id);
  if (!deleted) return null;

  if (deleted.imagePath && countReceiptsByImagePath(deleted.imagePath) === 0) {
    const absPath = path.join(dataDir, deleted.imagePath);
    fs.unlink(absPath, (err) => {
      if (err && err.code !== 'ENOENT') {
        console.error('Failed to delete receipt image:', absPath, err);
      }
    });
  }

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
    res.status(201).json({ imagePath: `uploads/${req.file.filename}` });
  });
});

router.use('/images', express.static(uploadsDir));

router.post('/extract', async (req, res) => {
  const { imagePath } = req.body;
  if (typeof imagePath !== 'string' || !imagePath) {
    return res.status(400).json({ error: 'imagePath is required' });
  }

  const resolvedDataDir = path.resolve(dataDir);
  const absPath = path.resolve(dataDir, imagePath);
  if (!absPath.startsWith(resolvedDataDir + path.sep)) {
    return res.status(400).json({ error: 'Invalid imagePath' });
  }
  if (!fs.existsSync(absPath)) {
    return res.status(404).json({ error: 'Image not found' });
  }

  try {
    const extracted = await extractReceiptFields(absPath);
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

// Registered before '/:id' so this fixed path isn't shadowed by the param route.
router.get('/categories', (req, res) => {
  res.json(getDistinctCategories());
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
    note: result.note !== undefined ? result.note : existing.note,
    imagePath: result.imagePath !== undefined ? result.imagePath : existing.imagePath,
  };

  res.json(updateReceipt(id, merged));
});

router.delete('/:id', (req, res) => {
  const deleted = deleteReceiptAndMaybeImage(Number(req.params.id));
  if (!deleted) return res.status(404).json({ error: 'Receipt not found' });
  res.status(204).end();
});

export default router;
