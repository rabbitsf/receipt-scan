import { useEffect, useState } from 'react';
import { loadPdf, renderPage } from '../pdfPageRenderer.js';

// Every page of a receipt's PDF, drawn with pdf.js (already used for import)
// so all browsers show all pages — embedded browser PDF viewers differ and
// some (e.g. iPhone Safari) show only the first page.
export default function ReceiptPdfPages({ url }) {
  const [pages, setPages] = useState([]);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    const urls = [];
    (async () => {
      try {
        const blob = await (await fetch(url)).blob();
        const pdf = await loadPdf(blob);
        for (let n = 1; n <= pdf.numPages && !cancelled; n++) {
          const image = await renderPage(pdf, n, 1600, 0.85);
          const objectUrl = URL.createObjectURL(image);
          urls.push(objectUrl);
          if (!cancelled) setPages((p) => [...p, objectUrl]);
        }
      } catch (err) {
        if (!cancelled) setError(err.message);
      }
    })();
    return () => {
      cancelled = true;
      urls.forEach((u) => URL.revokeObjectURL(u));
    };
  }, [url]);

  return (
    <div className="image-modal-pdf">
      {error && <p className="form-error">Couldn't show this PDF ({error}).</p>}
      {!error && pages.length === 0 && <p>Loading PDF…</p>}
      {pages.map((src, i) => (
        <img key={src} src={src} alt={`Receipt page ${i + 1}`} />
      ))}
      <a className="button-link secondary" href={url} target="_blank" rel="noreferrer">
        Open PDF
      </a>
    </div>
  );
}
