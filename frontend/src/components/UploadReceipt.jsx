import { useState } from 'react';
import ReceiptForm from './ReceiptForm.jsx';
import { uploadReceiptImage, extractReceiptFields, createReceipt } from '../api.js';
import { emptyReceiptValues as emptyValues, toFormValues } from '../receiptFields.js';

export default function UploadReceipt({ onDone }) {
  const [status, setStatus] = useState('idle'); // idle | uploading | extracting | review | saved
  const [imagePath, setImagePath] = useState(null);
  const [queue, setQueue] = useState([emptyValues]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [savedCount, setSavedCount] = useState(0);
  const [notice, setNotice] = useState(null);

  async function handleFileSelected(e) {
    const file = e.target.files[0];
    e.target.value = '';
    if (!file) return;

    setNotice(null);
    setStatus('uploading');
    try {
      const { imagePath: uploadedPath } = await uploadReceiptImage(file);
      setImagePath(uploadedPath);

      setStatus('extracting');
      try {
        const extracted = await extractReceiptFields(uploadedPath);
        if (extracted.length === 0) {
          setNotice('No receipts were detected in this photo. You can still enter the details manually below.');
          setQueue([emptyValues]);
        } else {
          setQueue(extracted.map(toFormValues));
        }
      } catch (extractErr) {
        setNotice(
          `Automatic scanning failed (${extractErr.message}). You can still enter the details manually below.`,
        );
        setQueue([emptyValues]);
      }
      setCurrentIndex(0);
      setSavedCount(0);
      setStatus('review');
    } catch (uploadErr) {
      setNotice(uploadErr.message);
      setStatus('idle');
    }
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
    setImagePath(null);
    setQueue([emptyValues]);
    setCurrentIndex(0);
    setSavedCount(0);
    setNotice(null);
  }

  const isMultiple = queue.length > 1;
  const isLastInQueue = currentIndex + 1 >= queue.length;

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
          {notice && <p className="form-error">{notice}</p>}
        </>
      )}

      {status === 'uploading' && <p>Uploading…</p>}
      {status === 'extracting' && <p>Scanning receipt…</p>}

      {status === 'review' && (
        <>
          {notice && <p className="form-warning">{notice}</p>}
          {isMultiple && (
            <p className="status-message">
              Found {queue.length} receipts in this photo — reviewing receipt {currentIndex + 1} of {queue.length}
            </p>
          )}
          <ReceiptForm
            key={currentIndex}
            initialValues={queue[currentIndex]}
            imagePath={imagePath}
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
