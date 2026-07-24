import Foundation

struct MonthTotal: Identifiable {
    let month: Int
    let total: Double
    var id: Int { month }
}

struct CategoryTotal: Identifiable, Equatable {
    let category: String
    let total: Double
    var id: String { category }
}

struct YearSummary {
    let year: Int
    let yearTotal: Double
    let priorYear: Int
    let priorYearTotal: Double
    let monthlyTotals: [MonthTotal]
    let categoryTotals: [CategoryTotal]
}

/// Ported from `backend/src/services/receiptsRepository.js:getYearSummary` —
/// same shape (year total, prior-year total, 12-entry monthly breakdown,
/// category breakdown sorted descending with "Uncategorized" for nil).
/// There it's computed via SQL `SUM`/`GROUP BY`; here, since the whole
/// dataset already lives on-device via `@Query`, it's the same in-memory
/// aggregation approach as `ReceiptFilter.swift` (Slice 4) — right-sized for
/// a personal, single-user local dataset.
enum DashboardSummary {
    static func compute(from receipts: [Receipt], year: Int, calendar: Calendar = .current) -> YearSummary {
        let priorYear = year - 1

        let yearReceipts = receipts.filter { calendar.component(.year, from: $0.date) == year }
        let priorYearReceipts = receipts.filter { calendar.component(.year, from: $0.date) == priorYear }

        let yearTotal = yearReceipts.reduce(0) { $0 + $1.totalCost }
        let priorYearTotal = priorYearReceipts.reduce(0) { $0 + $1.totalCost }

        var monthlySums = [Int: Double](minimumCapacity: 12)
        for receipt in yearReceipts {
            let month = calendar.component(.month, from: receipt.date)
            monthlySums[month, default: 0] += receipt.totalCost
        }
        let monthlyTotals = (1...12).map { MonthTotal(month: $0, total: monthlySums[$0] ?? 0) }

        var categorySums: [String: Double] = [:]
        for receipt in yearReceipts {
            let category = receipt.category?.isEmpty == false ? receipt.category! : "Uncategorized"
            categorySums[category, default: 0] += receipt.totalCost
        }
        let categoryTotals = categorySums
            .map { CategoryTotal(category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }

        return YearSummary(
            year: year,
            yearTotal: yearTotal,
            priorYear: priorYear,
            priorYearTotal: priorYearTotal,
            monthlyTotals: monthlyTotals,
            categoryTotals: categoryTotals
        )
    }
}
