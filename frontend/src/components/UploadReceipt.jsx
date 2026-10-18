import { useState } from 'react';
import ReceiptForm from './ReceiptForm.jsx';
import ScanCostDialog from './ScanCostDialog.jsx';
import { uploadReceiptImage, extractReceiptFields, createReceipt } from '../api.js';
import { emptyReceiptValues as emptyValues, toFormValues } from '../receiptFields.js';
import { costSummary, scanFiles } from '../pdfImport.js';

// A review entry: { values, imagePath, pdfPath, sourceLabel, notices }.
const blankEntry = { values: emptyValues, imagePath: null, pdfPath: null, sourceLabel: null, notices: [] };

export default function UploadReceipt({ onDone }) {
  const [status, setStatus] = useState('idle'); // idle | uploading | extracting | review | saved
  const [queue, setQueue] = useState([blankEntry]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [savedCount, setSavedCount] = useState(0);
  const [notice, setNotice] = useState(null);
  const [progress, setProgress] = useState(null);
  const [pendingPdfs, setPendingPdfs] = useState(null); // { files, summary } while the cost popup is open

  function startReview(entries, message = null) {
    setQueue(entries.length ? entries : [blankEntry]);
    setNotice(message);
    setCurrentIndex(0);
    setSavedCount(0);
    setStatus('review');
  }

  // A photo: every receipt found in it shares that photo.
  async function handleFileSelected(e) {
    const file = e.target.files[0];
    e.target.value = '';
    if (!file) return;

    setNotice(null);
    setStatus('uploading');
    let imagePath;
    try {
      ({ imagePath } = await uploadReceiptImage(file));
    } catch (uploadErr) {
      setNotice(uploadErr.message);
      setStatus('idle');
      return;
    }
    setStatus('extracting');
    try {
      const extracted = await extractReceiptFields([imagePath]);
      if (extracted.length === 0) {
        startReview([{ ...blankEntry, imagePath }], 'No receipts were detected. You can still enter the details manually below.');
      } else {
        startReview(extracted.map((r) => ({ ...blankEntry, values: toFormValues(r), imagePath })));
      }
    } catch (extractErr) {
      startReview(
        [{ ...blankEntry, imagePath }],
        `Automatic scanning failed (${extractErr.message}). You can still enter the details manually below.`,
      );
    }
  }

  // PDFs: show page counts and estimated cost first; the user chooses.
  async function handlePdfsSelected(e) {
    const files = Array.from(e.target.files);
    e.target.value = '';
    if (!files.length) return;
    setNotice(null);
    setStatus('uploading');
    try {
      setPendingPdfs({ files, summary: await costSummary(files) });
    } catch (err) {
      setNotice(err.message);
    }
    setStatus('idle');
  }

  async function runPdfScan(quickScan) {
    const { files, summary } = pendingPdfs;
    setPendingPdfs(null);
    setStatus('extracting');
    const entries = await scanFiles(files, { quickScan, limits: summary.limits }, (n, count) =>
      setProgress(count > 1 ? `Scanning file ${n} of ${count}…` : null),
    );
    setProgress(null);
    startReview(entries);
  }

  async function handleSave(values) {
    await createReceipt(values);
    const nextSavedCount = savedCount + 1;
    setSavedCount(nextSavedCount);

    if (currentIndex + 1 < queue.length) {
      setCurrentIndex(currentIndex + 1);
    } else {
      setStatus('saved');
    }
  }

  function handleReset() {
    setStatus('idle');
    setQueue([blankEntry]);
    setCurrentIndex(0);
    setSavedCount(0);
    setNotice(null);
  }

  const isMultiple = queue.length > 1;
  const isLastInQueue = currentIndex + 1 >= queue.length;
  const entry = queue[currentIndex];

  return (
    <div className="upload-receipt">
      {onDone && (
        <button type="button" className="back-link" onClick={() => onDone(null)}>
          ← Back to list
        </button>
      )}
      <h2>Add a Receipt</h2>

      {status === 'idle' && (
        <>
          <label className="file-input">
            Choose a receipt photo
            <input
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
              onChange={handleFileSelected}
            />
          </label>
          <label className="file-input">
            Import PDFs (you can pick several)
            <input type="file" accept="application/pdf" multiple onChange={handlePdfsSelected} />
          </label>
          {notice && <p className="form-error">{notice}</p>}
        </>
      )}

      {status === 'uploading' && <p>Reading files…</p>}
      {status === 'extracting' && <p>{progress ?? 'Scanning receipt…'}</p>}

      {pendingPdfs && (
        <ScanCostDialog summary={pendingPdfs.summary} onChoose={runPdfScan} onCancel={() => setPendingPdfs(null)} />
      )}

      {status === 'review' && (
        <>
          {notice && <p className="form-warning">{notice}</p>}
          {isMultiple && (
            <p className="status-message">
              Found {queue.length} receipts — reviewing receipt {currentIndex + 1} of {queue.length}
            </p>
          )}
          {entry.sourceLabel && <p className="settings-section-hint">{entry.sourceLabel}</p>}
          {entry.notices.map((n) => (
            <p key={n} className="form-warning">
              {n}
            </p>
          ))}
          <ReceiptForm
            key={currentIndex}
            initialValues={entry.values}
            imagePath={entry.imagePath}
            pdfPath={entry.pdfPath}
            submitLabel={isLastInQueue ? 'Save Receipt' : 'Save & Review Next'}
            onSubmit={handleSave}
            onCancel={handleReset}
          />
        </>
      )}

      {status === 'saved' && (
        <div>
          <p className="status-message">
            {savedCount === 1 ? 'Receipt saved.' : `${savedCount} receipts saved.`}
          </p>
          <div className="form-actions">
            <button type="button" onClick={handleReset}>
              Add another receipt
            </button>
            {onDone && (
              <button type="button" className="secondary" onClick={() => onDone()}>
                Back to list
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
