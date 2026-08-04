// Ad-hoc receipt bundling, e.g. "Business Trip to NY" — deliberately
// simpler than categories.js: there's no predefined list (every group is
// invented by the user), so there's no merge-with-predefined step. The
// backend's `GET /api/receipts/groups` already returns the full
// deduplicated, sorted list (in-use values + Settings-created ones) — the
// frontend uses it directly as the picker's option list.
export const CUSTOM_GROUP_VALUE = '__custom_group__';
