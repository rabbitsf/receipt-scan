import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const dataDir = path.join(__dirname, '../../data');
export const uploadsDir = path.join(dataDir, 'uploads');

// Creating uploadsDir (recursive) also creates dataDir as its parent.
fs.mkdirSync(uploadsDir, { recursive: true });
