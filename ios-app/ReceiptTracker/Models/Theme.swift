import SwiftUI

/// App-wide visual tokens for the card-based, teal-accented redesign
/// (2026-07-25). `AccentColor` (the asset catalog color) was updated to
/// match this same teal, so anything already using `.accentColor` picks
/// this up for free — these are the additional tokens that don't fit
/// that single color (card shape/elevation, the summary card's wash
/// background, chip backgrounds).
enum Theme {
    static let cardCornerRadius: CGFloat = 14
    static let chipCornerRadius: CGFloat = 20

    static let cardShadowColor = Color.black.opacity(0.08)
    static let cardShadowRadius: CGFloat = 6
    static let cardShadowY: CGFloat = 2

    /// The wash background behind the "This Month" summary card.
    static let summaryCardBackground = Color.accentColor.opacity(0.16)

    /// A given category's pastel chip/badge background, derived from its
    /// solid `CategoryOptions.color(for:)` rather than a second palette —
    /// one color per category, two opacities for two contexts (solid row
    /// icon vs. pastel chip).
    static func chipBackground(for category: String?) -> Color {
        CategoryOptions.color(for: category).opacity(0.16)
    }

    /// Deliberately NOT tied to category color — the Note badge needs to
    /// read as its own distinct kind of tag wherever it appears next to a
    /// category name/dot, not blend into that color language.
    static let notePillBackground = Color.purple.opacity(0.15)
    static let notePillForeground = Color.purple
}
