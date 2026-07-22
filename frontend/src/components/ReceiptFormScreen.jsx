import { useEffect, useState } from 'react';
import ReceiptForm from './ReceiptForm.jsx';
import { getReceipt, createReceipt, updateReceipt } from '../api.js';

export default function ReceiptFormScreen({ receiptId, onDone }) {
  const isEditing = receiptId != null;
  const [receipt, setReceipt] = useState(null);
  const [loading, setLoading] = useState(isEditing);
  const [loadError, setLoadError] = useState(null);

  useEffect(() => {
    if (!isEditing) return;
    let cancelled = false;
    setLoading(true);
    getReceipt(receiptId)
      .then((r) => {
        if (!cancelled) setReceipt(r);
      })
      .catch((err) => {
        if (!cancelled) setLoadError(err.message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [receiptId, isEditing]);

  async function handleSubmit(values) {
    const saved = isEditing ? await updateReceipt(receiptId, values) : await createReceipt(values);
    onDone(saved);
  }

  return (
    <div className="receipt-form-screen">
      <button type="button" className="back-link" onClick={() => onDone(null)}>
        ← Back to list
      </button>
      <h2>{isEditing ? 'Edit Receipt' : 'Add Receipt Manually'}</h2>

      {isEditing && loading && <p>Loading receipt…</p>}
      {isEditing && loadError && <p className="form-error">{loadError}</p>}

      {(!isEditing || (!loading && !loadError)) && (
        <ReceiptForm
          initialValues={receipt ?? undefined}
          imagePath={receipt?.imagePath ?? null}
          submitLabel={isEditing ? 'Save Changes' : 'Save Receipt'}
          onSubmit={handleSubmit}
          onCancel={() => onDone(null)}
        />
      )}
    </div>
  );
}
