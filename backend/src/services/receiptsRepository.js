import { db } from '../db/index.js';
import { toCents, toDollars } from '../utils/money.js';

function rowToReceipt(row) {
  if (!row) return null;
  return {
    id: row.id,
    date: row.date,
    totalCost: toDollars(row.total_cost_cents),
    merchant: row.merchant,
    description: row.description,
    category: row.category,
    note: row.note,
    imagePath: row.image_path,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

const insertStmt = db.prepare(`
  INSERT INTO receipts (date, total_cost_cents, merchant, description, category, note, image_path)
  VALUES (@date, @total_cost_cents, @merchant, @description, @category, @note, @image_path)
`);

const selectByIdStmt = db.prepare('SELECT * FROM receipts WHERE id = ?');

const updateStmt = db.prepare(`
  UPDATE receipts
  SET date = @date,
      total_cost_cents = @total_cost_cents,
      merchant = @merchant,
      description = @description,
      category = @category,
      note = @note,
      image_path = @image_path,
      updated_at = datetime('now')
  WHERE id = @id
`);

const deleteStmt = db.prepare('DELETE FROM receipts WHERE id = ?');

export function listReceipts({ year, month, q, category } = {}) {
  const conditions = [];
  const params = {};

  if (year && month) {
    conditions.push('date LIKE @datePrefix');
    params.datePrefix = `${year}-${String(month).padStart(2, '0')}-%`;
  } else if (year) {
    conditions.push('date LIKE @datePrefix');
    params.datePrefix = `${year}-%`;
  } else if (month) {
    conditions.push('substr(date, 6, 2) = @month');
    params.month = String(month).padStart(2, '0');
  }

  if (q) {
    conditions.push("(merchant LIKE @q OR description LIKE @q OR printf('%.2f', total_cost_cents / 100.0) LIKE @q)");
    params.q = `%${q}%`;
  }

  if (category) {
    conditions.push('category = @category');
    params.category = category;
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const stmt = db.prepare(`SELECT * FROM receipts ${where} ORDER BY date DESC, id DESC`);
  return stmt.all(params).map(rowToReceipt);
}

export function getReceiptById(id) {
  return rowToReceipt(selectByIdStmt.get(id));
}

export function getReceiptsByIds(ids) {
  if (!ids || ids.length === 0) return [];
  const placeholders = ids.map(() => '?').join(', ');
  const stmt = db.prepare(`SELECT * FROM receipts WHERE id IN (${placeholders}) ORDER BY date DESC, id DESC`);
  return stmt.all(...ids).map(rowToReceipt);
}

export function createReceipt({ date, totalCost, merchant, description, category, note, imagePath }) {
  const info = insertStmt.run({
    date,
    total_cost_cents: toCents(totalCost),
    merchant: merchant ?? null,
    description: description ?? null,
    category: category ?? null,
    note: note ?? null,
    image_path: imagePath ?? null,
  });
  return getReceiptById(info.lastInsertRowid);
}

export function updateReceipt(id, { date, totalCost, merchant, description, category, note, imagePath }) {
  const existing = selectByIdStmt.get(id);
  if (!existing) return null;

  updateStmt.run({
    id,
    date,
    total_cost_cents: toCents(totalCost),
    merchant: merchant ?? null,
    description: description ?? null,
    category: category ?? null,
    note: note ?? null,
    image_path: imagePath ?? existing.image_path,
  });
  return getReceiptById(id);
}

export function deleteReceipt(id) {
  const existing = rowToReceipt(selectByIdStmt.get(id));
  if (!existing) return null;
  deleteStmt.run(id);
  return existing;
}

export function getDistinctCategories() {
  const rows = db
    .prepare("SELECT DISTINCT category FROM receipts WHERE category IS NOT NULL AND category != '' ORDER BY category")
    .all();
  return rows.map((r) => r.category);
}

export function countReceiptsByImagePath(imagePath) {
  const row = db.prepare('SELECT COUNT(*) AS count FROM receipts WHERE image_path = ?').get(imagePath);
  return row.count;
}

export function getYearSummary(year) {
  const yearNum = Number(year);

  const yearTotalRow = db
    .prepare("SELECT COALESCE(SUM(total_cost_cents), 0) AS cents FROM receipts WHERE date LIKE @prefix")
    .get({ prefix: `${yearNum}-%` });

  const priorYearTotalRow = db
    .prepare("SELECT COALESCE(SUM(total_cost_cents), 0) AS cents FROM receipts WHERE date LIKE @prefix")
    .get({ prefix: `${yearNum - 1}-%` });

  const monthlyRows = db
    .prepare(
      "SELECT substr(date, 6, 2) AS month, SUM(total_cost_cents) AS cents FROM receipts WHERE date LIKE @prefix GROUP BY month",
    )
    .all({ prefix: `${yearNum}-%` });

  const monthlyMap = new Map(monthlyRows.map((r) => [Number(r.month), r.cents]));
  const monthlyTotals = Array.from({ length: 12 }, (_, i) => ({
    month: i + 1,
    total: toDollars(monthlyMap.get(i + 1) ?? 0),
  }));

  const categoryRows = db
    .prepare(
      `SELECT COALESCE(category, 'Uncategorized') AS category, SUM(total_cost_cents) AS cents
       FROM receipts WHERE date LIKE @prefix GROUP BY category ORDER BY cents DESC`,
    )
    .all({ prefix: `${yearNum}-%` });

  const categoryTotals = categoryRows.map((r) => ({
    category: r.category,
    total: toDollars(r.cents),
  }));

  return {
    year: yearNum,
    yearTotal: toDollars(yearTotalRow.cents),
    monthlyTotals,
    categoryTotals,
    priorYear: yearNum - 1,
    priorYearTotal: toDollars(priorYearTotalRow.cents),
  };
}
