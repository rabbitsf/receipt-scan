import Foundation

/// Builds the filename used when uploading a receipt's photo to Google
/// Drive. Not a real filesystem — Drive tolerates duplicate names in one
/// folder — but a readable, mostly-safe name (still portable if the user
/// later downloads it to any OS) is nicer than a bare UUID.
enum DriveUploadFilename {
    /// "{date}_{merchant}.jpg", sanitized. Falls back to `fallbackID` (a
    /// stable per-receipt string, e.g. derived from its persistent model
    /// ID) in place of the merchant when it's nil/blank, so same-day
    /// no-merchant receipts still get distinct names.
    static func make(date: Date, merchant: String?, fallbackID: String, fileExtension: String = "jpg") -> String {
        let datePart = DateOnly.string(from: date)
        let sanitizedMerchant = sanitize(merchant ?? "")
        let namePart = sanitizedMerchant.isEmpty ? fallbackID : sanitizedMerchant
        return "\(datePart)_\(namePart).\(fileExtension)"
    }

    /// Replaces characters that are invalid or awkward in filenames on
    /// common filesystems with `-`, then collapses repeated whitespace and
    /// trims the edges. Deliberately keeps spaces (rather than replacing
    /// them too) — Drive filenames read better with them, and Drive itself
    /// has no filesystem-style restriction against them.
    private static func sanitize(_ raw: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let replaced = String(raw.unicodeScalars.map { invalidCharacters.contains($0) ? "-" : Character($0) })
        let collapsed = replaced.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
