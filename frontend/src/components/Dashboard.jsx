import { useEffect, useState } from 'react';
import { getYearSummary } from '../api.js';

const CURRENT_YEAR = new Date().getFullYear();
const YEAR_OPTIONS = Array.from({ length: 6 }, (_, i) => CURRENT_YEAR - i);
const MONTH_NAMES = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

export default function Dashboard({ onDone }) {
  const [year, setYear] = useState(CURRENT_YEAR);
  const [summary, setSummary] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    getYearSummary(year)
      .then((data) => {
        if (!cancelled) setSummary(data);
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
  }, [year]);

  const diff = summary ? summary.yearTotal - summary.priorYearTotal : null;
  const maxMonthTotal = summary ? Math.max(1, ...summary.monthlyTotals.map((m) => m.total)) : 1;

  return (
    <div className="dashboard">
      <button type="button" className="back-link" onClick={() => onDone()}>
        ← Back to list
      </button>

      <div className="dashboard-header">
        <h2>Dashboard</h2>
        <label>
          Year
          <select value={year} onChange={(e) => setYear(Number(e.target.value))}>
            {YEAR_OPTIONS.map((y) => (
              <option key={y} value={y}>
                {y}
              </option>
            ))}
          </select>
        </label>
      </div>

      {loading && <p>Loading summary…</p>}
      {error && <p className="form-error">{error}</p>}

      {!loading && summary && (
        <>
          <div className="stat-row">
            <div className="stat-card">
              <span className="stat-label">{summary.year} total</span>
              <span className="stat-value">${summary.yearTotal.toFixed(2)}</span>
            </div>
            <div className="stat-card">
              <span className="stat-label">{summary.priorYear} total</span>
              <span className="stat-value">${summary.priorYearTotal.toFixed(2)}</span>
            </div>
            <div className="stat-card">
              <span className="stat-label">Change vs {summary.priorYear}</span>
              <span className="stat-value">
                {diff >= 0 ? '▲' : '▼'} ${Math.abs(diff).toFixed(2)}
              </span>
            </div>
          </div>

          <table className="dashboard-table">
            <thead>
              <tr>
                <th>Month</th>
                <th>Total</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {summary.monthlyTotals.map((m) => (
                <tr key={m.month}>
                  <td>{MONTH_NAMES[m.month - 1]}</td>
                  <td className="amount">${m.total.toFixed(2)}</td>
                  <td className="bar-cell">
                    <span
                      className="bar"
                      style={{ width: `${(m.total / maxMonthTotal) * 100}%` }}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </div>
  );
}
