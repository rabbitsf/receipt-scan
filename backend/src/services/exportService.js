import PDFDocument from 'pdfkit';
import ExcelJS from 'exceljs';

function pad(value, width) {
  const s = String(value ?? '');
  return s.length >= width ? `${s.slice(0, width - 1)}…` : s.padEnd(width);
}

export function generateReceiptsPdf(receipts) {
  const doc = new PDFDocument({ margin: 40, size: 'A4' });
  const chunks = [];
  doc.on('data', (chunk) => chunks.push(chunk));
  const done = new Promise((resolve) => doc.on('end', () => resolve(Buffer.concat(chunks))));

  const total = receipts.reduce((sum, r) => sum + r.totalCost, 0);

  doc.font('Helvetica-Bold').fontSize(18).text('Receipts');
  doc.moveDown(0.5);
  doc
    .font('Helvetica')
    .fontSize(11)
    .text(`${receipts.length} receipt${receipts.length === 1 ? '' : 's'} — Total: $${total.toFixed(2)}`);
  doc.moveDown();

  doc.font('Courier-Bold').fontSize(9);
  doc.text(`${pad('Date', 12)}${pad('Merchant', 22)}${pad('Total', 10)}${pad('Description', 40)}`);
  doc.moveDown(0.2);
  doc.font('Courier').fontSize(9);

  for (const r of receipts) {
    doc.text(`${pad(r.date, 12)}${pad(r.merchant, 22)}${pad(`$${r.totalCost.toFixed(2)}`, 10)}${pad(r.description, 40)}`);
  }

  doc.end();
  return done;
}

export async function generateReceiptsExcel(receipts) {
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet('Receipts');

  sheet.columns = [
    { header: 'Date', key: 'date', width: 14 },
    { header: 'Merchant', key: 'merchant', width: 28 },
    { header: 'Total', key: 'total', width: 12 },
    { header: 'Description', key: 'description', width: 40 },
  ];
  sheet.getRow(1).font = { bold: true };

  for (const r of receipts) {
    sheet.addRow({ date: r.date, merchant: r.merchant, total: r.totalCost, description: r.description });
  }
  sheet.getColumn('total').numFmt = '$#,##0.00';

  const total = receipts.reduce((sum, r) => sum + r.totalCost, 0);
  const totalsRow = sheet.addRow({
    merchant: `Total (${receipts.length} receipt${receipts.length === 1 ? '' : 's'})`,
    total,
  });
  totalsRow.font = { bold: true };

  return workbook.xlsx.writeBuffer();
}
