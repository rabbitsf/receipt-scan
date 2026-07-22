export function toCents(dollars) {
  return Math.round(Number(dollars) * 100);
}

export function toDollars(cents) {
  return Math.round(cents) / 100;
}
