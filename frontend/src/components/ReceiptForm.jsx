import { useState } from 'react';
import { uploadReceiptImage, extractReceiptFields } from '../api.js';
import { emptyReceiptValues as emptyValues, toFormValues } from '../receiptFields.js';

export default function ReceiptForm({ initialValues, imagePath: initialImagePath, onSubmit, submitLabel = 'Save', onCancel }) {
  const [values, setValues] = useState({ ...emptyValues, ...initialValues });
  const [imagePath, setImagePath] = useState(initialImagePath ?? null);
  const [uploadingImage, setUploadingImage] = useState(false);
  const [extractingImage, setExtractingImage] = useState(false);
  const [imageError, setImageError] = useState(null);
  const [extractNotice, setExtractNotice] = useState(null);
  const [error, setError] = useState(null);
  const [saving, setSaving] = useState(false);

  const imageUrl = imagePath ? `/api/receipts/images/${imagePath.replace(/^uploads\//, '')}` : null;

  function handleChange(e) {
    const { name, value } = e.target;
    setValues((v) => ({ ...v, [name]: value }));
  }

  async function handleImageSelected(e) {
    const file = e.target.files[0];
    e.target.value = '';
    if (!file) return;

    setImageError(null);
    setExtractNotice(null);
    setUploadingImage(true);
    let uploadedPath;
    try {
      ({ imagePath: uploadedPath } = await uploadReceiptImage(file));
      setImagePath(uploadedPath);
    } catch (err) {
      setImageError(err.message);
      return;
    } finally {
      setUploadingImage(false);
    }

    setExtractingImage(true);
    try {
      const extracted = await extractReceiptFields(uploadedPath);
      if (extracted.length === 0) {
        setExtractNotice('No receipt details were detected in this photo — please check the fields below.');
      } else {
        setValues(toFormValues(extracted[0]));
        if (extracted.length > 1) {
          setExtractNotice(
            `This photo contains ${extracted.length} receipts; the fields below were filled in from the first one. Add the others as separate receipts.`,
          );
        }
      }
    } catch (err) {
      setExtractNotice(`Automatic scanning failed (${err.message}) — please check the fields below.`);
    } finally {
      setExtractingImage(false);
    }
  }

  function handleDownloadPhoto() {
    if (!imageUrl) return;
    const link = document.createElement('a');
    link.href = imageUrl;
    link.download = '';
    link.click();
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);
    setSaving(true);
    try {
      await onSubmit({
        date: values.date,
        merchant: values.merchant,
        totalCost: Number(values.totalCost),
        description: values.description,
        imagePath: imagePath ?? null,
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  }

  return (
    <form className="receipt-form" onSubmit={handleSubmit}>
      {imagePath && (
        <>
          <img className="receipt-thumbnail" src={imageUrl} alt="Receipt" />
          <div className="form-actions">
            <button type="button" className="secondary" onClick={handleDownloadPhoto}>
              Download Photo
            </button>
          </div>
        </>
      )}

      <label className="file-input">
        {imagePath ? 'Replace photo' : 'Attach a photo (optional)'}
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
          onChange={handleImageSelected}
          disabled={uploadingImage || extractingImage}
        />
      </label>
      {uploadingImage && <p>Uploading photo…</p>}
      {extractingImage && <p>Scanning receipt…</p>}
      {imageError && <p className="form-error">{imageError}</p>}
      {extractNotice && <p className="form-warning">{extractNotice}</p>}

      <label>
        Date
        <input type="date" name="date" value={values.date} onChange={handleChange} required />
      </label>

      <label>
        Merchant
        <input type="text" name="merchant" value={values.merchant ?? ''} onChange={handleChange} />
      </label>

      <label>
        Total Cost
        <input
          type="number"
          step="0.01"
          min="0"
          name="totalCost"
          value={values.totalCost}
          onChange={handleChange}
          required
        />
      </label>

      <label>
        Description
        <textarea name="description" value={values.description ?? ''} onChange={handleChange} rows={3} />
      </label>

      {error && <p className="form-error">{error}</p>}

      <div className="form-actions">
        <button type="submit" disabled={saving || uploadingImage || extractingImage}>
          {saving ? 'Saving…' : submitLabel}
        </button>
        {onCancel && (
          <button type="button" className="secondary" onClick={onCancel} disabled={saving}>
            Cancel
          </button>
        )}
      </div>
    </form>
  );
}
