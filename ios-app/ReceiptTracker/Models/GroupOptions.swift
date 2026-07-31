import Foundation
import SwiftUI

/// Ad-hoc receipt bundling, e.g. "Business Trip to NY" — deliberately
/// simpler than `CategoryOptions`: there's no predefined list (every group
/// is invented by the user), so there's no `predefined` array or
/// merge-with-predefined step, just a lookup of whatever's currently in use.
enum GroupOptions {
    /// Selecting this in a group `Picker` means "show a free-text field
    /// instead" — same role as `CategoryOptions.customSentinel`, kept as a
    /// distinct string so the two never collide if ever compared directly.
    static let customSentinel = "__custom_group__"

    /// Distinct non-empty group values currently in use, sorted
    /// alphabetically. Unlike `CategoryOptions.mergeWithInUseCategories`,
    /// there's no predefined seed list to merge against. `customGroups`
    /// (default empty) adds Settings-created groups that don't have any
    /// receipt using them yet — see `CustomGroup`.
    static func availableGroups(from receipts: [Receipt], customGroups: [String] = []) -> [String] {
        let inUse = receipts.compactMap(\.group).filter { !$0.isEmpty }
        return Set(inUse).union(customGroups.filter { !$0.isEmpty }).sorted()
    }

    /// Number of receipts currently using this exact group — Settings uses
    /// this to block deleting a group that's still in use.
    static func usageCount(of group: String, in receipts: [Receipt]) -> Int {
        receipts.filter { $0.group == group }.count
    }

    /// Renames `group` to `newName` on every matching receipt in place
    /// (mutates the passed-in `Receipt` objects; the caller is responsible
    /// for saving the model context afterward). Mirrors
    /// `CategoryOptions.renameInUse(from:to:in:)`.
    static func renameInUse(from oldName: String, to newName: String, in receipts: [Receipt]) {
        for receipt in receipts where receipt.group == oldName {
            receipt.group = newName
            receipt.updatedAt = Date()
        }
    }

    /// Every group is equally arbitrary/user-invented — no predefined
    /// index to key off, so every group (including custom ones) goes
    /// through the same deterministic hash-based pick. Same technique as
    /// `CategoryOptions.color(for:)`'s custom-category fallback branch,
    /// own palette so a group's color doesn't coincidentally read as "the
    /// same visual language" as a category's.
    private static let palette: [Color] = [
        .indigo, .mint, .cyan, .brown, .purple, .orange, .teal, .pink,
    ]

    static func color(for group: String?) -> Color {
        guard let group, !group.isEmpty else {
            return .gray
        }
        let hash = group.unicodeScalars.reduce(into: 0) { result, scalar in
            result = (result &* 31) &+ Int(scalar.value)
        }
        return palette[abs(hash) % palette.count]
    }

    /// One fixed icon for every group — unlike `CategoryOptions.icon(for:)`,
    /// there's no semantic mapping possible for an arbitrary user-invented
    /// name, so there's nothing to look up.
    static func icon(for _: String?) -> String {
        "folder.fill"
    }
}
