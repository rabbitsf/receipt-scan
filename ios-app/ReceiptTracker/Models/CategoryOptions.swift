import Foundation

/// Ported from `frontend/src/categories.js` — same 8 predefined categories,
/// same "custom" concept. Unlike the web app (which fetches distinct
/// in-use categories from the backend via `GET /api/receipts/categories`),
/// this standalone app has no backend to ask — `mergeWithInUseCategories`
/// takes the equivalent from the local `@Query` result directly instead.
enum CategoryOptions {
    static let predefined = [
        "Office Supplies",
        "Travel",
        "Meals & Entertainment",
        "Utilities",
        "Software/Subscriptions",
        "Equipment",
        "Professional Services",
        "Other",
    ]

    /// Selecting this in a category `Picker` means "show a free-text field
    /// instead" — mirrors `CUSTOM_CATEGORY_VALUE` in `frontend/src/categories.js`.
    /// Distinct from `nil` (which means "no category set").
    static let customSentinel = "__custom__"

    /// Predefined categories first (stable order), then any custom
    /// categories already in use — appended alphabetically, deduplicated
    /// against the predefined set. Mirrors
    /// `frontend/src/categories.js:mergeCategoryOptions()`.
    static func mergeWithInUseCategories(_ inUseCategories: [String]) -> [String] {
        let extras = Set(inUseCategories).subtracting(predefined).sorted()
        return predefined + extras
    }
}
