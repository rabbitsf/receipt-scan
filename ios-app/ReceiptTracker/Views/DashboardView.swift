import SwiftUI
import SwiftData

/// Ported from `frontend/src/components/Dashboard.jsx` — year picker, 3 stat
/// cards (year total / prior-year total / change), monthly breakdown with
/// proportional bars, category breakdown with proportional bars.
struct DashboardView: View {
    @Query private var receipts: [Receipt]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedYear = Calendar.current.component(.year, from: Date())

    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    private var summary: YearSummary {
        DashboardSummary.compute(from: receipts, year: selectedYear)
    }

    private var change: Double {
        summary.yearTotal - summary.priorYearTotal
    }

    private var maxMonthTotal: Double {
        max(1, summary.monthlyTotals.map(\.total).max() ?? 1)
    }

    private var maxCategoryTotal: Double {
        max(1, summary.categoryTotals.map(\.total).max() ?? 1)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(ReceiptFilter.yearOptions, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .accessibilityIdentifier("dashboardYearPicker")
                }

                Section {
                    statRow(label: "\(summary.year) total", value: summary.yearTotal)
                    statRow(label: "\(summary.priorYear) total", value: summary.priorYearTotal)
                    HStack {
                        Text("Change vs \(summary.priorYear)")
                        Spacer()
                        Text("\(change >= 0 ? "▲" : "▼") \(abs(change), format: .currency(code: "USD"))")
                            .foregroundStyle(change >= 0 ? .green : .red)
                            .font(.callout.monospacedDigit())
                    }
                }

                Section("Monthly Breakdown") {
                    ForEach(summary.monthlyTotals) { monthTotal in
                        barRow(
                            label: Self.monthAbbreviations[monthTotal.month - 1],
                            total: monthTotal.total,
                            maxTotal: maxMonthTotal
                        )
                    }
                }

                if !summary.categoryTotals.isEmpty {
                    Section("By Category") {
                        ForEach(summary.categoryTotals) { categoryTotal in
                            barRow(
                                label: categoryTotal.category,
                                total: categoryTotal.total,
                                maxTotal: maxCategoryTotal
                            )
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statRow(label: String, value: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value, format: .currency(code: "USD"))
                .font(.callout.monospacedDigit())
        }
    }

    private func barRow(label: String, total: Double, maxTotal: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(total, format: .currency(code: "USD"))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(2, geometry.size.width * (total / maxTotal)), height: 6)
            }
            .frame(height: 6)
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: Receipt.self, inMemory: true)
}
