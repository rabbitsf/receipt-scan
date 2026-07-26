import Foundation
import SwiftUI

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

    /// One fixed, distinct color per predefined category (by index, so it
    /// stays stable even if a category is renamed elsewhere in this array).
    /// Custom categories beyond the predefined 8 still need a color
    /// wherever the UI shows a swatch, so they get a deterministic
    /// hash-based pick from the same palette instead of a second list to
    /// keep in sync — same palette entry for the same name every time,
    /// across every screen, with no per-category config required.
    private static let palette: [Color] = [
        .blue, .orange, .purple, .teal, .pink, .indigo, .brown, .mint,
    ]

    /// Single canonical color lookup — every view that shows a category
    /// (list row, pickers, dashboard bars) should call this rather than
    /// deriving its own color, so a given category always looks the same
    /// everywhere. `nil`/empty/"Uncategorized" (the `DashboardSummary`
    /// fallback label for receipts with no category) render as `.gray`.
    static func color(for category: String?) -> Color {
        guard let category, !category.isEmpty, category != "Uncategorized" else {
            return .gray
        }
        if let index = predefined.firstIndex(of: category) {
            return palette[index % palette.count]
        }
        let hash = category.unicodeScalars.reduce(into: 0) { result, scalar in
            result = (result &* 31) &+ Int(scalar.value)
        }
        return palette[abs(hash) % palette.count]
    }

    /// One SF Symbol per predefined category, keyed by name (unlike
    /// `color(for:)`, an icon can't be derived from array position — the
    /// symbol has to mean something). Custom categories and
    /// nil/empty/"Uncategorized" fall back to a generic tag icon rather
    /// than a second guessing scheme.
    private static let icons: [String: String] = [
        "Office Supplies": "paperclip",
        "Travel": "airplane",
        "Meals & Entertainment": "fork.knife",
        "Utilities": "bolt.fill",
        "Software/Subscriptions": "laptopcomputer",
        "Equipment": "wrench.and.screwdriver.fill",
        "Professional Services": "briefcase.fill",
        "Other": "ellipsis.circle.fill",
    ]

    /// Single canonical icon lookup, mirroring `color(for:)` — every view
    /// that shows a category icon should call this rather than picking
    /// its own symbol.
    static func icon(for category: String?) -> String {
        guard let category, !category.isEmpty, category != "Uncategorized" else {
            return "tag.fill"
        }
        return icons[category] ?? "tag.fill"
    }
}
