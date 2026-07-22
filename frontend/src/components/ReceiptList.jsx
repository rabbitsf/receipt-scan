import { useEffect, useState } from 'react';
import { listReceipts, deleteReceipt, bulkDeleteReceipts } from '../api.js';

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
  const [searchInput, setSearchInput] = useState('');
  const [query, setQuery] = useState('');
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [viewingImageUrl, setViewingImageUrl] = useState(null);

  useEffect(() => {
    const handle = setTimeout(() => setQuery(searchInput.trim()), 300);
    return () => clearTimeout(handle);
  }, [searchInput]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    listReceipts({ year, month, q: query })
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
  }, [year, month, query]);

  // Filter changes invalidate the currently-loaded row set, so drop any stale selection.
  useEffect(() => {
    setSelectedIds(new Set());
  }, [year, month, query]);

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

  const hasFilters = Boolean(year || month || query);

  function handleExport(format) {
    const params = new URLSearchParams();
    params.set('format', format);
    if (year) params.set('year', year);
    if (month) params.set('month', month);
    if (query) params.set('q', query);

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
                <td>{r.description}</td>
                <td className="row-actions">
                  {r.imagePath && (
                    <button
                      type="button"
                      className="secondary"
                      onClick={() =>
                        setViewingImageUrl(`/api/receipts/images/${r.imagePath.replace(/^uploads\//, '')}`)
                      }
                    >
                      View Receipt
                    </button>
                  )}
                  <button type="button" onClick={() => onEdit(r.id)}>
                    Edit
                  </button>
                  <button type="button" onClick={() => handleDelete(r.id)}>
                    Delete
                  </button>
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
