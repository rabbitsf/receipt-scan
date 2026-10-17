import express from 'express';
import { getOcrSettings, updateOcrSettings } from '../services/ocrService.js';

const router = express.Router();

router.get('/ocr', (req, res) => {
  res.json(getOcrSettings());
});

router.put('/ocr', (req, res) => {
  const { provider, models, keyWarningDismissed } = req.body || {};
  if (models !== undefined && (typeof models !== 'object' || models === null || Array.isArray(models))) {
    return res.status(400).json({ error: 'models must be an object of provider → model name' });
  }
  try {
    res.json(updateOcrSettings({ provider, models, keyWarningDismissed }));
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

export default router;
