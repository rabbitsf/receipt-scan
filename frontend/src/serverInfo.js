import { useEffect, useState } from 'react';

// Which server is serving this page — the Mac backend (`backend/`) or the
// iPhone app's "Web Access over Wi-Fi" server — read from `GET /api/health`.
// The two differ only in export formats and in where API keys are set up.
export const DEFAULT_SERVER_INFO = { host: 'computer', exportFormats: ['pdf', 'xlsx'] };

export const EXPORT_FORMAT_LABELS = { pdf: 'PDF', xlsx: 'Excel', csv: 'CSV' };

let cached = null;

export function getServerInfo() {
  if (!cached) {
    cached = fetch('/api/health')
      .then((res) => (res.ok ? res.json() : {}))
      .then((body) => ({
        host: body.host || DEFAULT_SERVER_INFO.host,
        exportFormats: Array.isArray(body.exportFormats) ? body.exportFormats : DEFAULT_SERVER_INFO.exportFormats,
      }))
      .catch(() => DEFAULT_SERVER_INFO);
  }
  return cached;
}

export function useServerInfo() {
  const [info, setInfo] = useState(DEFAULT_SERVER_INFO);
  useEffect(() => {
    getServerInfo().then(setInfo);
  }, []);
  return info;
}
