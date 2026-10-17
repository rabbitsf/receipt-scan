import { useEffect, useState } from 'react';
import { getOcrSettings, updateOcrSettings } from '../api.js';

// Shown once when the app loads if the selected scanning provider has no API
// key in backend/.env (and the user hasn't chosen "Don't show again").
// Scanning needs the key; everything else works without it. Mirrors the iOS
// "No API Key" launch alert in `ReceiptListView.swift`.
export default function MissingKeyWarning({ onAddKey }) {
  // All providers, so the message stays general: on first launch the user
  // hasn't chosen one yet.
  const [providers, setProviders] = useState(null);

  useEffect(() => {
    getOcrSettings()
      .then((settings) => {
        const selected = settings.providers[settings.provider];
        if (!selected.configured && !settings.keyWarningDismissed) setProviders(Object.values(settings.providers));
      })
      .catch(() => {}); // Never block the app over a reminder.
  }, []);

  if (!providers) return null;

  const orList = (items) => new Intl.ListFormat('en', { type: 'disjunction' }).format(items);

  async function handleDontShowAgain() {
    setProviders(null);
    await updateOcrSettings({ keyWarningDismissed: true }).catch(() => {});
  }

  return (
    <div className="image-modal-overlay">
      <div
        className="key-warning-dialog"
        role="alertdialog"
        aria-labelledby="key-warning-title"
        aria-describedby="key-warning-body"
      >
        <h3 id="key-warning-title">No API Key</h3>
        <p id="key-warning-body">
          Scanning receipt photos needs an API key from an AI provider ({orList(providers.map((p) => p.displayName))}).
          Add it to <code>backend/.env</code> as {orList(providers.map((p) => p.envVar))}, restart the backend, and
          choose that provider in Settings. You can still add receipts by hand.
        </p>
        <div className="key-warning-actions">
          <button
            type="button"
            onClick={() => {
              setProviders(null);
              onAddKey();
            }}
          >
            Add Key
          </button>
          <button type="button" className="secondary" onClick={() => setProviders(null)}>
            Not Now
          </button>
          <button type="button" className="secondary" onClick={handleDontShowAgain}>
            Don't Show Again
          </button>
        </div>
      </div>
    </div>
  );
}
