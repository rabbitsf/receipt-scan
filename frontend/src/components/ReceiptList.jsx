import { useEffect, useState } from 'react';
import { listReceipts, deleteReceipt, bulkDeleteReceipts, getCategories } from '../api.js';
import { CATEGORY_OPTIONS, mergeCategoryOptions } from '../categories.js';

const ICON_PROPS = {
  width: 16,
  height: 16,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 2,
  strokeLinecap: 'round',
  strokeLinejoin: 'round',
};

function ViewIcon() {
  return (
    <svg {...ICON_PROPS}>
      <path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

function EditIcon() {
  return (
    <svg {...ICON_PROPS}>
      <path d="M12 20h9" />
      <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z" />
    </svg>
  );
}

function DeleteIcon() {
  return (
    <svg {...ICON_PROPS}>
      <polyline points="3 6 5 6 21 6" />
      <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
      <path d="M10 11v6" />
      <path d="M14 11v6" />
      <path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" />
    </svg>
  );
}

const CURRENT_YEAR = new Date().getFullYear();
const YEAR_OPTIONS = Array.from({ length: 6 }, (_, i) => CURRENT_YEAR - i);
const MONTHS = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

export default function ReceiptList({ onAddPhoto, onAddManual, onEdit, onDashboard }) {
  const [receipts, setReceipts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const [year, setYear] = useState('');
  const [month, setMonth] = useState('');
  const [category, setCategory] = useState('');
  const [searchInput, setSearchInput] = useState('');
  const [query, setQuery] = useState('');
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [viewingImageUrl, setViewingImageUrl] = useState(null);
  const [categoryOptions, setCategoryOptions] = useState(CATEGORY_OPTIONS);

  useEffect(() => {
    getCategories()
      .then((custom) => setCategoryOptions(mergeCategoryOptions(custom)))
      .catch(() => {});
  }, []);

  useEffect(() => {
    const handle = setTimeout(() => setQuery(searchInput.trim()), 300);
    return () => clearTimeout(handle);
  }, [searchInput]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    listReceipts({ year, month, q: query, category })
      .then((data) => {
        if (!cancelled) setReceipts(data);
      })
      .catch((err) => {
        if (!cancelled) setError(err.message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [year, month, query, category]);

  // Filter changes invalidate the currently-loaded row set, so drop any stale selection.
  useEffect(() => {
    setSelectedIds(new Set());
  }, [year, month, query, category]);

  async function handleDelete(id) {
    if (!window.confirm('Delete this receipt?')) return;
    try {
      await deleteReceipt(id);
      setReceipts((rs) => rs.filter((r) => r.id !== id));
      setSelectedIds((prev) => {
        if (!prev.has(id)) return prev;
        const next = new Set(prev);
        next.delete(id);
        return next;
      });
    } catch (err) {
      setError(err.message);
    }
  }

  function toggleSelected(id) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }

  function toggleSelectAll() {
    setSelectedIds((prev) => (prev.size === receipts.length ? new Set() : new Set(receipts.map((r) => r.id))));
  }

  async function handleDeleteSelected() {
    if (!window.confirm(`Delete ${selectedIds.size} selected receipt(s)?`)) return;
    try {
      const ids = Array.from(selectedIds);
      await bulkDeleteReceipts(ids);
      setReceipts((rs) => rs.filter((r) => !selectedIds.has(r.id)));
      setSelectedIds(new Set());
    } catch (err) {
      setError(err.message);
    }
  }

  const hasFilters = Boolean(year || month || query || category);

  function handleExport(format) {
    const params = new URLSearchParams();
    params.set('format', format);
    if (year) params.set('year', year);
    if (month) params.set('month', month);
    if (query) params.set('q', query);
    if (category) params.set('category', category);

    const link = document.createElement('a');
    link.href = `/api/receipts/export?${params.toString()}`;
    link.click();
  }

  function handleExportSelected(format) {
    const params = new URLSearchParams();
    params.set('format', format);
    params.set('ids', Array.from(selectedIds).join(','));

    const link = document.createElement('a');
    link.href = `/api/receipts/export?${params.toString()}`;
    link.click();
  }

  return (
    <div className="receipt-list">
      <div className="form-actions">
        <button type="button" onClick={onAddPhoto}>
          Add via Photo
        </button>
        <button type="button" onClick={onAddManual}>
          Add Manually
        </button>
        <button type="button" className="secondary" onClick={onDashboard}>
          Dashboard
        </button>
      </div>

      <div className="filters">
        <label>
          Year
          <select value={year} onChange={(e) => setYear(e.target.value)}>
            <option value="">All years</option>
            {YEAR_OPTIONS.map((y) => (
              <option key={y} value={y}>
                {y}
              </option>
            ))}
          </select>
        </label>

        <label>
          Month
          <select value={month} onChange={(e) => setMonth(e.target.value)}>
            <option value="">All months</option>
            {MONTHS.map((name, i) => (
              <option key={name} value={i + 1}>
                {name}
              </option>
            ))}
          </select>
        </label>

        <label>
          Category
          <select value={category} onChange={(e) => setCategory(e.target.value)}>
            <option value="">All categories</option>
            {categoryOptions.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>

        <label>
          Search
          <input
            type="text"
            placeholder="Merchant, description, or amount"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
          />
        </label>
      </div>

      <div className="form-actions">
        <button type="button" className="secondary" onClick={() => handleExport('pdf')}>
          Export PDF
        </button>
        <button type="button" className="secondary" onClick={() => handleExport('xlsx')}>
          Export Excel
        </button>
      </div>

      {selectedIds.size > 0 && (
        <div className="form-actions bulk-actions">
          <span>{selectedIds.size} selected</span>
          <button type="button" onClick={handleDeleteSelected}>
            Delete Selected
          </button>
          <button type="button" className="secondary" onClick={() => handleExportSelected('pdf')}>
            Export Selected PDF
          </button>
          <button type="button" className="secondary" onClick={() => handleExportSelected('xlsx')}>
            Export Selected Excel
          </button>
        </div>
      )}

      {error && <p className="form-error">{error}</p>}
      {loading && <p>Loading receipts…</p>}
      {!loading && receipts.length === 0 && (
        <p>{hasFilters ? 'No receipts match the current filters.' : 'No receipts yet.'}</p>
      )}

      {!loading && receipts.length > 0 && (
        <table className="receipts-table">
          <thead>
            <tr>
              <th>
                <input
                  type="checkbox"
                  checked={selectedIds.size === receipts.length}
                  onChange={toggleSelectAll}
                  aria-label="Select all receipts"
                />
              </th>
              <th>Date</th>
              <th>Merchant</th>
              <th>Total</th>
              <th>Description</th>
              <th>Category</th>
              <th>Note</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {receipts.map((r) => (
              <tr key={r.id}>
                <td>
                  <input
                    type="checkbox"
                    checked={selectedIds.has(r.id)}
                    onChange={() => toggleSelected(r.id)}
                    aria-label={`Select receipt from ${r.date}`}
                  />
                </td>
                <td>{r.date}</td>
                <td>{r.merchant}</td>
                <td className="amount">${r.totalCost.toFixed(2)}</td>
                <td className="description-cell" title={r.description || ''}>
                  {r.description}
                </td>
                <td>{r.category || 'Uncategorized'}</td>
                <td className="note-cell" title={r.note || ''}>
                  {r.note}
                </td>
                <td>
                  <div className="row-actions">
                    {r.imagePath && (
                      <button
                        type="button"
                        className="icon-button secondary"
                        title="View Receipt"
                        aria-label="View Receipt"
                        onClick={() =>
                          setViewingImageUrl(`/api/receipts/images/${r.imagePath.replace(/^uploads\//, '')}`)
                        }
                      >
                        <ViewIcon />
                      </button>
                    )}
                    <button
                      type="button"
                      className="icon-button"
                      title="Edit"
                      aria-label="Edit"
                      onClick={() => onEdit(r.id)}
                    >
                      <EditIcon />
                    </button>
                    <button
                      type="button"
                      className="icon-button"
                      title="Delete"
                      aria-label="Delete"
                      onClick={() => handleDelete(r.id)}
                    >
                      <DeleteIcon />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {viewingImageUrl && (
        <div className="image-modal-overlay" onClick={() => setViewingImageUrl(null)}>
          <div className="image-modal-content" onClick={(e) => e.stopPropagation()}>
            <button type="button" className="secondary image-modal-close" onClick={() => setViewingImageUrl(null)}>
              Close
            </button>
            <img className="image-modal-img" src={viewingImageUrl} alt="Original receipt" />
          </div>
        </div>
      )}
    </div>
  );
}
