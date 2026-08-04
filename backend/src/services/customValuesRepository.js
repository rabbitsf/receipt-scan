import { db } from '../db/index.js';

// Backs Settings-created categories/groups — independent of any receipt row
// (see `custom_values` table in `db/index.js`). Mirrors iOS's
// `CustomCategory`/`CustomGroup` SwiftData models and their
// `usageCount(of:in:)`/`renameInUse(from:to:in:)` helpers. Predefined
// categories are NOT stored here — only user-added custom entries; Settings
// is expected to keep the 8 predefined categories fixed/uneditable at the
// route/frontend layer, same as iOS.
//
// Operates by NAME, not `custom_values.id` — a category/group can be
// "known" (appears in pickers, renameable/deletable from Settings) purely
// because a receipt uses it, with no backing `custom_values` row at all
// (it was only ever typed ad-hoc into a receipt's category/group field).
// The frontend has no id for that case, only the name, so rename/delete
// must be addressable by name (same reasoning as iOS's
// `SettingsView.categoryRow`, which looks up `customCategories.first(where:
// { $0.name == oldName })` rather than requiring a pre-existing row).
const VALID_KINDS = new Set(['category', 'group']);

function assertValidKind(kind) {
  if (!VALID_KINDS.has(kind)) {
    throw new Error(`Invalid kind: ${kind}`);
  }
}

// `kind` is always one of the two literal strings checked above before
// this is called — never derived from unvalidated user input — so it's
// safe to interpolate into the column name here (SQLite has no
// parameterized-identifier syntax).
function receiptColumnFor(kind) {
  return kind === 'category' ? 'category' : '"group"';
}

export function listCustomValues(kind) {
  assertValidKind(kind);
  return db.prepare('SELECT id, name FROM custom_values WHERE kind = ? ORDER BY name').all(kind);
}

export function createCustomValue(kind, name) {
  assertValidKind(kind);
  const trimmed = String(name ?? '').trim();
  if (!trimmed) return null;
  const existing = db.prepare('SELECT id, name FROM custom_values WHERE kind = ? AND name = ?').get(kind, trimmed);
  if (existing) return existing;
  const info = db.prepare('INSERT INTO custom_values (kind, name) VALUES (?, ?)').run(kind, trimmed);
  return { id: info.lastInsertRowid, name: trimmed };
}

export function usageCount(kind, name) {
  assertValidKind(kind);
  const column = receiptColumnFor(kind);
  const row = db.prepare(`SELECT COUNT(*) AS count FROM receipts WHERE ${column} = ?`).get(name);
  return row.count;
}

// Renames `oldName` to `newName`: cascades to every receipt currently using
// `oldName`, AND upserts the `custom_values` row (updates it if one exists
// for `oldName`, inserts a fresh one for `newName` otherwise) so the
// renamed value keeps appearing in pickers even if every receipt using it
// is later deleted or changed. Single canonical place for this two-step
// operation (mirrors iOS's `renameInUse` + `CustomCategory.name =` pairing
// in `SettingsView.swift`).
export function renameCustomValue(kind, oldName, newName) {
  assertValidKind(kind);
  const trimmed = String(newName ?? '').trim();
  if (!trimmed || trimmed === oldName) return null;

  const column = receiptColumnFor(kind);
  const existingRow = db.prepare('SELECT id, name FROM custom_values WHERE kind = ? AND name = ?').get(kind, oldName);

  const rename = db.transaction(() => {
    if (existingRow) {
      db.prepare('UPDATE custom_values SET name = ? WHERE id = ?').run(trimmed, existingRow.id);
    } else {
      db.prepare('INSERT INTO custom_values (kind, name) VALUES (?, ?)').run(kind, trimmed);
    }
    db.prepare(`UPDATE receipts SET ${column} = ?, updated_at = datetime('now') WHERE ${column} = ?`).run(
      trimmed,
      oldName,
    );
  });
  rename();
  return { name: trimmed };
}

// Blocked if the value is still in use by any receipt (returns the count
// instead of deleting) — mirrors iOS's Settings delete-blocked-with-alert
// behavior. Deleting a name with no backing `custom_values` row (only ever
// in-use-derived, never explicitly added via Settings) succeeds as a no-op
// on the table — there's nothing to remove, and since usage is required to
// be zero to reach this point, the name simply stops being offered.
export function deleteCustomValueIfUnused(kind, name) {
  assertValidKind(kind);
  const count = usageCount(kind, name);
  if (count > 0) {
    return { deleted: false, count };
  }
  db.prepare('DELETE FROM custom_values WHERE kind = ? AND name = ?').run(kind, name);
  return { deleted: true, count: 0 };
}
