import Foundation
import SwiftData

/// THE place for Settings-style category/group management — listing,
/// adding, renaming (cascades to receipts) and deleting (blocked while in
/// use). Called by `SettingsView` and by the Web Access API
/// (`WebAPIRouter`), so the phone screen and the browser follow one set of
/// rules. Mirrors `backend/src/services/customValuesRepository.js`.
///
/// The 8 predefined categories stay fixed: they can't be added, renamed to
/// or renamed from here.
@MainActor
enum CustomValueStore {
    enum Kind {
        case category
        case group
    }

    enum DeleteOutcome: Equatable {
        case deleted
        case blocked(usageCount: Int)
    }

    /// Names shown in Settings' editable list: every non-predefined category
    /// (Settings-created or typed on a receipt), or every group.
    static func listedNames(_ kind: Kind, receipts: [Receipt], customNames: [String]) -> [String] {
        switch kind {
        case .category:
            return Array(
                CategoryOptions.mergeWithInUseCategories(receipts.compactMap(\.category), customCategories: customNames)
                    .dropFirst(CategoryOptions.predefined.count)
            )
        case .group:
            return GroupOptions.availableGroups(from: receipts, customGroups: customNames)
        }
    }

    static func listedNames(_ kind: Kind, in context: ModelContext) -> [String] {
        listedNames(kind, receipts: allReceipts(in: context), customNames: customNames(kind, in: context))
    }

    static func usageCount(of name: String, kind: Kind, in context: ModelContext) -> Int {
        let receipts = allReceipts(in: context)
        switch kind {
        case .category: return CategoryOptions.usageCount(of: name, in: receipts)
        case .group: return GroupOptions.usageCount(of: name, in: receipts)
        }
    }

    /// Returns the saved (trimmed) name, or nil when the name is blank or a
    /// predefined category. Adding a name that already exists is a no-op
    /// that still returns it.
    @discardableResult
    static func add(_ name: String, kind: Kind, in context: ModelContext) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPredefined(trimmed, kind) else { return nil }
        if !listedNames(kind, in: context).contains(trimmed) {
            insertCustom(trimmed, kind: kind, in: context)
            try? context.save()
        }
        return trimmed
    }

    /// Renames on every receipt using `oldName` and keeps the new name
    /// listed even if those receipts later change. Returns the new name, or
    /// nil when the rename isn't allowed.
    @discardableResult
    static func rename(_ oldName: String, to newName: String, kind: Kind, in context: ModelContext) -> String? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName, !isPredefined(trimmed, kind), !isPredefined(oldName, kind) else {
            return nil
        }
        let receipts = allReceipts(in: context)
        switch kind {
        case .category:
            CategoryOptions.renameInUse(from: oldName, to: trimmed, in: receipts)
            if let existing = try? context.fetch(FetchDescriptor<CustomCategory>()).first(where: { $0.name == oldName }) {
                existing.name = trimmed
            } else {
                insertCustom(trimmed, kind: kind, in: context)
            }
        case .group:
            GroupOptions.renameInUse(from: oldName, to: trimmed, in: receipts)
            if let existing = try? context.fetch(FetchDescriptor<CustomGroup>()).first(where: { $0.name == oldName }) {
                existing.name = trimmed
            } else {
                insertCustom(trimmed, kind: kind, in: context)
            }
        }
        try? context.save()
        return trimmed
    }

    static func delete(_ name: String, kind: Kind, in context: ModelContext) -> DeleteOutcome {
        let count = usageCount(of: name, kind: kind, in: context)
        guard count == 0 else { return .blocked(usageCount: count) }
        switch kind {
        case .category:
            for row in (try? context.fetch(FetchDescriptor<CustomCategory>())) ?? [] where row.name == name {
                context.delete(row)
            }
        case .group:
            for row in (try? context.fetch(FetchDescriptor<CustomGroup>())) ?? [] where row.name == name {
                context.delete(row)
            }
        }
        try? context.save()
        return .deleted
    }

    /// Settings' "can't delete" wording, shared with the web API's 409 error.
    static func blockedMessage(_ name: String, usageCount count: Int) -> String {
        "\"\(name)\" is used by \(count) receipt\(count == 1 ? "" : "s") and can't be deleted. Change or clear that field on those receipts first."
    }

    private static func isPredefined(_ name: String, _ kind: Kind) -> Bool {
        kind == .category && CategoryOptions.predefined.contains(name)
    }

    private static func allReceipts(in context: ModelContext) -> [Receipt] {
        (try? context.fetch(FetchDescriptor<Receipt>())) ?? []
    }

    private static func customNames(_ kind: Kind, in context: ModelContext) -> [String] {
        switch kind {
        case .category: return ((try? context.fetch(FetchDescriptor<CustomCategory>())) ?? []).map(\.name)
        case .group: return ((try? context.fetch(FetchDescriptor<CustomGroup>())) ?? []).map(\.name)
        }
    }

    private static func insertCustom(_ name: String, kind: Kind, in context: ModelContext) {
        switch kind {
        case .category: context.insert(CustomCategory(name: name))
        case .group: context.insert(CustomGroup(name: name))
        }
    }
}
