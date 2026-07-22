import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { db } from './db/index.js';
import receiptsRouter from './routes/receipts.js';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors());
app.use(express.json());

app.get('/api/health', (req, res) => {
  const { count } = db.prepare('SELECT COUNT(*) AS count FROM receipts').get();
  res.json({ status: 'ok', receiptCount: count });
});

app.use('/api/receipts', receiptsRouter);

app.listen(PORT, () => {
  console.log(`Receipt tracker backend listening on http://localhost:${PORT}`);
});
