import Foundation
import SwiftData

/// A category name created from Settings, independent of whether any
/// receipt uses it yet. `CategoryOptions.mergeWithInUseCategories`'s
/// `customCategories` parameter merges these in alongside `predefined` and
/// in-use receipt categories — this table exists solely so a category can
/// appear in the picker BEFORE any receipt references it. Distinct from
/// `predefined` (Task 1 decision: the 8 predefined categories stay fixed,
/// this is only for user-added custom ones).
@Model
final class CustomCategory {
    var name: String

    init(name: String) {
        self.name = name
    }
}
