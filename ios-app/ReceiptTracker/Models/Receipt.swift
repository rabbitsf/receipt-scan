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
    /// The receipt's own pages when it came from a PDF import (just its
    /// pages, or the whole file — see `PDFPageAssignment`). `imageData` then
    /// holds its first page as a photo, so list/thumbnail code keeps working.
    /// nil for photo receipts. Added 2026-10-18; optional, so existing
    /// stores migrate automatically.
    @Attribute(.externalStorage) var pdfData: Data?
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
        imageData: Data? = nil,
        pdfData: Data? = nil
    ) {
        self.date = date
        self.totalCost = totalCost
        self.merchant = merchant
        self.itemDescription = itemDescription
        self.category = category
        self.group = group
        self.note = note
        self.imageData = imageData
        self.pdfData = pdfData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
