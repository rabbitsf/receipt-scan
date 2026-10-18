import { QUICK_SCAN_PAGES } from '../pdfPageRenderer.js';
import { formatUsd } from '../pdfImport.js';

// The PDF import cost popup (every PDF import): each file's page count, the
// estimated cost, and the choice to scan all pages, only the first few, or
// nothing. Mirrors the iOS cost alert in `ReceiptFormView.swift`.

export default function ScanCostDialog({ summary, onChoose, onCancel }) {
  const multiple = summary.files.length > 1;
  return (
    <div className="image-modal-overlay">
      <div className="key-warning-dialog" role="alertdialog" aria-labelledby="scan-cost-title">
        <h3 id="scan-cost-title">{multiple ? `Scan ${summary.files.length} PDFs?` : 'Scan This PDF?'}</h3>
        <ul className="scan-cost-files">
          {summary.files.map((f) => (
            <li key={f.name}>
              {f.name} — {f.pages} page{f.pages === 1 ? '' : 's'}
            </li>
          ))}
        </ul>
        <p>
          {summary.allPagesUsd == null
            ? `The cost can't be estimated for the custom model ${summary.model}.`
            : `Estimated ${summary.providerName} cost is shown on each button. Each file is scanned on its own; you'll review every receipt found before saving.`}
        </p>
        <div className="key-warning-actions">
          <button type="button" onClick={() => onChoose(false)}>
            Scan all {summary.totalPages} pages ({formatUsd(summary.allPagesUsd)})
          </button>
          {summary.quickScanPages < summary.totalPages && (
            <button type="button" className="secondary" onClick={() => onChoose(true)}>
              Scan first {QUICK_SCAN_PAGES} pages{multiple ? ' of each' : ''} ({formatUsd(summary.quickScanUsd)})
            </button>
          )}
          <button type="button" className="secondary" onClick={onCancel}>
            Cancel
          </button>
        </div>
      </div>
    </div>
  );
}
