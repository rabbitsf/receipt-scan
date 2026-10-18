import { getOcrSettings, updateOcrSettings } from './api.js';

// Asks before receipts are sent to an AI provider, when the server requires
// it. Only the iPhone app's Web Access server reports `aiConsent` (App Store
// guideline 5.1.2(i)); the Mac backend doesn't, so this returns true there.
// Mirrors iOS's `AIScanConsent` prompt — same wording, same per-provider answer.
// Returns true when scanning may go ahead.
export async function ensureScanConsent() {
  let settings;
  try {
    settings = await getOcrSettings();
  } catch {
    return true; // the scan itself will report any problem
  }
  const { provider, providers, aiConsent, aiConsentExplanation } = settings;
  if (!aiConsent || aiConsent[provider] || !providers[provider]?.configured) return true;
  const allowed = window.confirm(
    `Send receipts to ${providers[provider].displayName}?\n\n${aiConsentExplanation?.[provider] ?? ''}`,
  );
  if (allowed) await updateOcrSettings({ aiConsent: { [provider]: true } });
  return allowed;
}
