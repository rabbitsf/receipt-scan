# Receipt Tracker

A web app for keeping every receipt straight for tax time. Attach a photo and
let Claude Vision extract the date, merchant, total, and description automatically,
or enter receipts by hand. Filter, search, and export to PDF or Excel.

## Features

- **Photo upload with OCR** — attach a receipt photo and have its fields
  auto-extracted via Claude Vision; a single photo can contain multiple receipts
- **Manual entry** — add or edit receipts by hand
- **Auto-rescan on photo replace** — swapping a receipt's photo re-runs OCR and
  refreshes the fields
- **View Receipt** — see the full-resolution original photo for any receipt
  from the list, or download it
- **Filter & search** — by year, month, merchant, description, or amount
- **Bulk actions** — multi-select receipts to delete or export together
- **Export** — download the current (or selected) receipts as PDF or Excel
- **Dashboard** — year total, monthly breakdown, and prior-year comparison

## Tech stack

- **Frontend** — React + Vite
- **Backend** — Node.js (Express) + better-sqlite3
- **OCR** — Claude Vision via the Anthropic SDK
- **Exports** — pdfkit (PDF), exceljs (Excel)

## Getting started

### Prerequisites

- Node.js 18+
- An [Anthropic API key](https://console.anthropic.com/) for OCR extraction

### Setup

```bash
npm run install:all
cp backend/.env.example backend/.env
# then edit backend/.env and set ANTHROPIC_API_KEY
```

### Run

```bash
npm run dev
```

This starts the backend (`http://localhost:3001`) and frontend
(`http://localhost:5173`) together. The frontend dev server proxies `/api`
requests to the backend.

## Project structure

```
backend/
  src/
    db/              SQLite connection + schema
    routes/           HTTP endpoints (receipts CRUD, export, image serving)
    services/          OCR extraction, PDF/Excel export, receipts data access
    utils/
  data/                SQLite database + uploaded images (gitignored)
frontend/
  src/
    components/        React components (list, form, upload, dashboard)
    api.js              Backend HTTP client
```
