import Foundation

/// Filter/search logic for the receipts list, ported from the web app's
/// `ReceiptList.jsx` (year/month/category dropdowns + debounced search
/// matching merchant/description/amount). There, filtering happens via SQL
/// `WHERE` clauses in `receiptsRepository.js:listReceipts`; here, since the
/// whole dataset already lives on-device via SwiftData's `@Query` and is
/// small (personal, single-user), filtering the fetched array in-memory is
/// the right-sized approach — no `#Predicate` macro needed (which can't
/// express date-component extraction like "year of this Date" anyway).
enum ReceiptFilter {
    static var yearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return (0..<6).map { currentYear - $0 }
    }

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    static func apply(
        to receipts: [Receipt],
        year: Int? = nil,
        month: Int? = nil,
        category: String? = nil,
        searchText: String = "",
        calendar: Calendar = .current
    ) -> [Receipt] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return receipts.filter { receipt in
            if let year, calendar.component(.year, from: receipt.date) != year {
                return false
            }
            if let month, calendar.component(.month, from: receipt.date) != month {
                return false
            }
            if let category, receipt.category != category {
                return false
            }
            if !trimmedSearch.isEmpty {
                let merchantMatch = receipt.merchant?.lowercased().contains(trimmedSearch) ?? false
                let descriptionMatch = receipt.itemDescription?.lowercased().contains(trimmedSearch) ?? false
                let amountMatch = String(format: "%.2f", receipt.totalCost).contains(trimmedSearch)
                guard merchantMatch || descriptionMatch || amountMatch else { return false }
            }
            return true
        }
    }
}
