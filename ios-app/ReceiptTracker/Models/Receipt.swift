import Foundation
import SwiftData

/// On-device receipt record. Fully standalone — no relation to
/// `backend/`'s SQLite schema or its `receipts` table; this is a separate
/// dataset stored locally via SwiftData.
///
/// Named `itemDescription`, not `description`: SwiftData `@Model` classes
/// are backed by Core Data's `NSManagedObject`, which subclasses `NSObject`
/// and already declares a non-optional `description` — naming a stored
/// property `description` collides with that.
@Model
final class Receipt {
    var date: Date
    var totalCost: Double
    var merchant: String?
    var itemDescription: String?
    var category: String?
    /// Ad-hoc bundling label, e.g. "Business Trip to NY" — distinct from
    /// `category` (a fixed expense taxonomy): a receipt has at most one
    /// group, invented freely by the user rather than picked from a
    /// predefined list. See `GroupOptions`.
    var group: String?
    var note: String?
    var imageData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        date: Date,
        totalCost: Double,
        merchant: String? = nil,
        itemDescription: String? = nil,
        category: String? = nil,
        group: String? = nil,
        note: String? = nil,
        imageData: Data? = nil
    ) {
        self.date = date
        self.totalCost = totalCost
        self.merchant = merchant
        self.itemDescription = itemDescription
        self.category = category
        self.group = group
        self.note = note
        self.imageData = imageData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
