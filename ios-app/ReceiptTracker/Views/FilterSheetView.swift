import SwiftUI

struct FilterSheetView: View {
    @Binding var selectedYear: Int?
    @Binding var selectedMonth: Int?
    @Binding var selectedCategory: String?
    let availableCategories: [String]
    @Binding var selectedGroup: String?
    let availableGroups: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Year", selection: $selectedYear) {
                    Text("All years").tag(Int?.none)
                    ForEach(ReceiptFilter.yearOptions, id: \.self) { year in
                        Text(String(year)).tag(Int?.some(year))
                    }
                }
                .accessibilityIdentifier("yearFilterPicker")

                Picker("Month", selection: $selectedMonth) {
                    Text("All months").tag(Int?.none)
                    ForEach(Array(ReceiptFilter.monthNames.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(Int?.some(index + 1))
                    }
                }
                .accessibilityIdentifier("monthFilterPicker")

                Picker("Category", selection: $selectedCategory) {
                    Text("All categories").tag(String?.none)
                    ForEach(availableCategories, id: \.self) { category in
                        Text(category).tag(String?.some(category))
                    }
                }
                .accessibilityIdentifier("categoryFilterPicker")

                Picker("Group", selection: $selectedGroup) {
                    Text("All groups").tag(String?.none)
                    ForEach(availableGroups, id: \.self) { group in
                        Text(group).tag(String?.some(group))
                    }
                }
                .accessibilityIdentifier("groupFilterPicker")

                if selectedYear != nil || selectedMonth != nil || selectedCategory != nil || selectedGroup != nil {
                    Button("Clear Filters", role: .destructive) {
                        selectedYear = nil
                        selectedMonth = nil
                        selectedCategory = nil
                        selectedGroup = nil
                    }
                    .accessibilityIdentifier("clearFiltersButton")
                }
            }
            .navigationTitle("Filter")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    FilterSheetView(selectedYear: .constant(nil), selectedMonth: .constant(nil), selectedCategory: .constant(nil), availableCategories: [], selectedGroup: .constant(nil), availableGroups: [])
}
