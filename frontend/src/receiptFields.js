export const emptyReceiptValues = { date: '', merchant: '', totalCost: '', description: '', category: '', note: '' };

export function toFormValues(fields) {
  return {
    date: fields.date ?? '',
    merchant: fields.merchant ?? '',
    totalCost: fields.total_cost ?? '',
    description: fields.description ?? '',
  };
}
