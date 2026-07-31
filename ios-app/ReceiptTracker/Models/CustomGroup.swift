import Foundation
import SwiftData

/// A group name created from Settings, independent of whether any receipt
/// uses it yet. Mirrors `CustomCategory`, but for `GroupOptions` — Group has
/// no predefined list at all, so every Settings-created group goes through
/// this table (`GroupOptions.availableGroups`'s `customGroups` parameter).
@Model
final class CustomGroup {
    var name: String

    init(name: String) {
        self.name = name
    }
}
