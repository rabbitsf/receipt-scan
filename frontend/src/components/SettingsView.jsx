import { useEffect, useState } from 'react';
import { CATEGORY_OPTIONS } from '../categories.js';
import { useServerInfo } from '../serverInfo.js';
import {
  getCategories,
  createCategory,
  renameCategory,
  deleteCategory,
  getGroups,
  createGroup,
  renameGroup,
  deleteGroup,
  getOcrSettings,
  updateOcrSettings,
} from '../api.js';

// Mirrors the iOS Settings screen: create/rename/delete Category and Group
// values directly, instead of only via the ad-hoc "Custom category…"/"New
// group…" entry on the Add Receipt form. The 8 predefined categories stay
// fixed/uneditable; only custom entries are manageable here.
export default function SettingsView({ onDone }) {
  const [categories, setCategories] = useState([]);
  const { host } = useServerInfo();
  const [groups, setGroups] = useState([]);
  const [error, setError] = useState(null);

  const [newCategoryName, setNewCategoryName] = useState('');
  const [renamingCategory, setRenamingCategory] = useState(null);
  const [renameCategoryText, setRenameCategoryText] = useState('');

  const [newGroupName, setNewGroupName] = useState('');
  const [renamingGroup, setRenamingGroup] = useState(null);
  const [renameGroupText, setRenameGroupText] = useState('');

  const [ocrSettings, setOcrSettings] = useState(null);
  const [modelText, setModelText] = useState('');
  const [ocrStatus, setOcrStatus] = useState(null);
  const [savingOcr, setSavingOcr] = useState(false);

  function applyOcrSettings(settings) {
    setOcrSettings(settings);
    setModelText(settings.providers[settings.provider].model);
  }

  function loadOcrSettings() {
    getOcrSettings()
      .then(applyOcrSettings)
      .catch((err) => setError(err.message));
  }

  // Switch the UI to the new provider immediately, and keep the row
  // disabled until the server confirms — otherwise a quick model edit + Save
  // could land on the previous provider, or be wiped by the late response.
  async function handleProviderChange(e) {
    const provider = e.target.value;
    setError(null);
    setOcrStatus(null);
    applyOcrSettings({ ...ocrSettings, provider });
    setSavingOcr(true);
    try {
      applyOcrSettings(await updateOcrSettings({ provider }));
    } catch (err) {
      setError(err.message);
    } finally {
      setSavingOcr(false);
    }
  }

  async function handleSaveModel(e) {
    e.preventDefault();
    setError(null);
    setSavingOcr(true);
    try {
      applyOcrSettings(
        await updateOcrSettings({
          models: { [ocrSettings.provider]: modelText },
        }),
      );
      setOcrStatus('Saved.');
    } catch (err) {
      setError(err.message);
    } finally {
      setSavingOcr(false);
    }
  }

  function loadCategories() {
    getCategories()
      .then(setCategories)
      .catch((err) => setError(err.message));
  }

  function loadGroups() {
    getGroups()
      .then(setGroups)
      .catch((err) => setError(err.message));
  }

  useEffect(() => {
    loadOcrSettings();
    loadCategories();
    loadGroups();
  }, []);

  // `getCategories()` already returns predefined + in-use + Settings-created
  // values merged — the predefined 8 get their own read-only rows above
  // this list, so exclude them here.
  const customCategories = categories.filter((c) => !CATEGORY_OPTIONS.includes(c));

  async function handleAddCategory(e) {
    e.preventDefault();
    const trimmed = newCategoryName.trim();
    if (!trimmed) return;
    setError(null);
    try {
      await createCategory(trimmed);
      setNewCategoryName('');
      loadCategories();
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleDeleteCategory(name) {
    setError(null);
    try {
      await deleteCategory(name);
      loadCategories();
    } catch (err) {
      setError(
        err.count != null
          ? `"${name}" is used by ${err.count} receipt${err.count === 1 ? '' : 's'} and can't be deleted. Change or clear that field on those receipts first.`
          : err.message,
      );
    }
  }

  function beginRenameCategory(name) {
    setRenamingCategory(name);
    setRenameCategoryText('');
    setError(null);
  }

  async function handleSubmitRenameCategory(e) {
    e.preventDefault();
    const trimmed = renameCategoryText.trim();
    if (!trimmed) return;
    setError(null);
    try {
      await renameCategory(renamingCategory, trimmed);
      setRenamingCategory(null);
      loadCategories();
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleAddGroup(e) {
    e.preventDefault();
    const trimmed = newGroupName.trim();
    if (!trimmed) return;
    setError(null);
    try {
      await createGroup(trimmed);
      setNewGroupName('');
      loadGroups();
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleDeleteGroup(name) {
    setError(null);
    try {
      await deleteGroup(name);
      loadGroups();
    } catch (err) {
      setError(
        err.count != null
          ? `"${name}" is used by ${err.count} receipt${err.count === 1 ? '' : 's'} and can't be deleted. Change or clear that field on those receipts first.`
          : err.message,
      );
    }
  }

  function beginRenameGroup(name) {
    setRenamingGroup(name);
    setRenameGroupText('');
    setError(null);
  }

  async function handleSubmitRenameGroup(e) {
    e.preventDefault();
    const trimmed = renameGroupText.trim();
    if (!trimmed) return;
    setError(null);
    try {
      await renameGroup(renamingGroup, trimmed);
      setRenamingGroup(null);
      loadGroups();
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <div className="settings-view">
      <button type="button" className="back-link" onClick={() => onDone()}>
        ← Back to list
      </button>
      <h2>Settings</h2>

      {error && <p className="form-error">{error}</p>}

      {ocrSettings && (
        <div className="settings-section">
          <h3>Receipt Scanning</h3>
          <p className="settings-section-hint">
            Choose which AI reads your receipt photos. API keys live{' '}
            {host === 'iphone' ? (
              'in the iPhone app (Settings → Receipt Scanning)'
            ) : (
              <>
                in <code>backend/.env</code>
              </>
            )}
            , not
            here.
            Leave the model blank to use the default.
          </p>
          <form className="settings-inline-form" onSubmit={handleSaveModel}>
            <fieldset className="settings-inline-fieldset" disabled={savingOcr}>
              <select
                aria-label="Scanning provider"
                value={ocrSettings.provider}
                onChange={handleProviderChange}
              >
                {Object.entries(ocrSettings.providers).map(([id, p]) => (
                  <option key={id} value={id}>
                    {p.displayName}
                  </option>
                ))}
              </select>
              <input
                type="text"
                aria-label="Model"
                placeholder={ocrSettings.providers[ocrSettings.provider].defaultModel}
                value={modelText}
                onChange={(e) => {
                  setModelText(e.target.value);
                  setOcrStatus(null);
                }}
              />
              <button type="submit">Save</button>
            </fieldset>
          </form>
          {ocrSettings.providers[ocrSettings.provider].configured ? (
            <p className="settings-section-hint settings-ocr-status">
              {ocrStatus || `${ocrSettings.providers[ocrSettings.provider].displayName} API key found.`}
            </p>
          ) : (
            <p className="form-error settings-ocr-status">
              No {ocrSettings.providers[ocrSettings.provider].displayName} API key configured —{' '}
              {host === 'iphone' ? (
                'add it in the iPhone app under Settings → Receipt Scanning.'
              ) : (
                <>
                  set <code>{ocrSettings.providers[ocrSettings.provider].envVar}</code> in <code>backend/.env</code>{' '}
                  and restart the backend.
                </>
              )}{' '}
              Scanning will fail until then.
            </p>
          )}
        </div>
      )}

      <div className="settings-section">
        <h3>Categories</h3>
        <p className="settings-section-hint">
          The 8 built-in categories can't be renamed or removed. Categories added here — or typed as
          "Custom category…" on a receipt — show up in the category picker right away.
        </p>
        <ul className="settings-list">
          {CATEGORY_OPTIONS.map((c) => (
            <li key={c} className="predefined">
              {c}
            </li>
          ))}
          {customCategories.map((c) =>
            renamingCategory === c ? (
              <li key={c}>
                <form className="settings-inline-form" onSubmit={handleSubmitRenameCategory}>
                  <input
                    type="text"
                    placeholder={c}
                    value={renameCategoryText}
                    onChange={(e) => setRenameCategoryText(e.target.value)}
                    autoFocus
                  />
                  <button type="submit">Save</button>
                  <button type="button" className="secondary" onClick={() => setRenamingCategory(null)}>
                    Cancel
                  </button>
                </form>
              </li>
            ) : (
              <li key={c}>
                <span>{c}</span>
                <span className="settings-row-actions">
                  <button type="button" className="secondary" onClick={() => beginRenameCategory(c)}>
                    Rename
                  </button>
                  <button type="button" className="secondary" onClick={() => handleDeleteCategory(c)}>
                    Delete
                  </button>
                </span>
              </li>
            ),
          )}
        </ul>
        <form className="settings-inline-form" onSubmit={handleAddCategory}>
          <input
            type="text"
            placeholder="New category"
            value={newCategoryName}
            onChange={(e) => setNewCategoryName(e.target.value)}
          />
          <button type="submit">Add</button>
        </form>
      </div>

      <div className="settings-section">
        <h3>Groups</h3>
        <p className="settings-section-hint">
          Groups added here — or typed as "New group…" on a receipt — show up in the group picker right
          away.
        </p>
        <ul className="settings-list">
          {groups.map((g) =>
            renamingGroup === g ? (
              <li key={g}>
                <form className="settings-inline-form" onSubmit={handleSubmitRenameGroup}>
                  <input
                    type="text"
                    placeholder={g}
                    value={renameGroupText}
                    onChange={(e) => setRenameGroupText(e.target.value)}
                    autoFocus
                  />
                  <button type="submit">Save</button>
                  <button type="button" className="secondary" onClick={() => setRenamingGroup(null)}>
                    Cancel
                  </button>
                </form>
              </li>
            ) : (
              <li key={g}>
                <span>{g}</span>
                <span className="settings-row-actions">
                  <button type="button" className="secondary" onClick={() => beginRenameGroup(g)}>
                    Rename
                  </button>
                  <button type="button" className="secondary" onClick={() => handleDeleteGroup(g)}>
                    Delete
                  </button>
                </span>
              </li>
            ),
          )}
        </ul>
        <form className="settings-inline-form" onSubmit={handleAddGroup}>
          <input
            type="text"
            placeholder="New group"
            value={newGroupName}
            onChange={(e) => setNewGroupName(e.target.value)}
          />
          <button type="submit">Add</button>
        </form>
      </div>
    </div>
  );
}
