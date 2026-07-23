export const CATEGORY_OPTIONS = [
  'Office Supplies',
  'Travel',
  'Meals & Entertainment',
  'Utilities',
  'Software/Subscriptions',
  'Equipment',
  'Professional Services',
  'Other',
];

export const CUSTOM_CATEGORY_VALUE = '__custom__';

// Predefined categories first (stable order), then any custom categories
// already in use (e.g. from the backend's distinct-categories list) appended
// alphabetically, deduplicated against the predefined set.
export function mergeCategoryOptions(customCategories = []) {
  const extras = customCategories.filter((c) => c && !CATEGORY_OPTIONS.includes(c)).sort();
  return [...CATEGORY_OPTIONS, ...extras];
}
