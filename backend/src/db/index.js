import Database from 'better-sqlite3';
import path from 'node:path';
import { dataDir } from '../utils/paths.js';

const dbPath = path.join(dataDir, 'receipts.db');

export const db = new Database(dbPath);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS receipts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    total_cost_cents INTEGER NOT NULL,
    merchant TEXT,
    description TEXT,
    category TEXT,
    note TEXT,
    image_path TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_receipts_date ON receipts(date);
`);

// CREATE TABLE IF NOT EXISTS only affects brand-new DB files; existing DBs
// need these columns added explicitly. Safe to run on every boot.
const existingColumns = new Set(db.prepare('PRAGMA table_info(receipts)').all().map((c) => c.name));
for (const column of ['category', 'note']) {
  if (!existingColumns.has(column)) {
    db.exec(`ALTER TABLE receipts ADD COLUMN ${column} TEXT`);
  }
}
