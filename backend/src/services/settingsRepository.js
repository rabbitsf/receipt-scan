import { db } from '../db/index.js';

// Backs the `app_settings` key/value table (see `db/index.js`). Generic on
// purpose — callers own the meaning of each key (e.g. `ocrService.js`).

export function getSetting(key) {
  const row = db.prepare('SELECT value FROM app_settings WHERE key = ?').get(key);
  return row ? row.value : null;
}

export function setSetting(key, value) {
  db.prepare(
    'INSERT INTO app_settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
  ).run(key, value);
}

export function deleteSetting(key) {
  db.prepare('DELETE FROM app_settings WHERE key = ?').run(key);
}
