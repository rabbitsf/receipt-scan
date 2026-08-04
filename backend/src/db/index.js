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
    "group" TEXT,
    note TEXT,
    image_path TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_receipts_date ON receipts(date);
`);

// CREATE TABLE IF NOT EXISTS only affects brand-new DB files; existing DBs
// need these columns added explicitly. Safe to run on every boot.
// `group` is a SQL reserved word (GROUP BY) — always double-quote it as an
// identifier, both here and in every query that references the column.
const existingColumns = new Set(db.prepare('PRAGMA table_info(receipts)').all().map((c) => c.name));
for (const column of ['category', 'note', 'group']) {
  if (!existingColumns.has(column)) {
    db.exec(`ALTER TABLE receipts ADD COLUMN "${column}" TEXT`);
  }
}

// Persisted "known" categories/groups, independent of any receipt row —
// mirrors iOS's `CustomCategory`/`CustomGroup` SwiftData models. Exists so a
// value can appear in pickers before any receipt uses it (Settings-created
// values). `kind` is 'category' or 'group'; predefined categories are NOT
// stored here (they stay a hardcoded list, see `frontend/src/categories.js`
// and its future `groups.js` sibling) — only user-added custom entries.
db.exec(`
  CREATE TABLE IF NOT EXISTS custom_values (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL CHECK (kind IN ('category', 'group')),
    name TEXT NOT NULL,
    UNIQUE (kind, name)
  );
`);
