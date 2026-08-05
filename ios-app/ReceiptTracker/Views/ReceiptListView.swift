import SwiftUI
import SwiftData

struct ReceiptListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @Query(sort: \CustomCategory.name) private var customCategories: [CustomCategory]
    @Query(sort: \CustomGroup.name) private var customGroups: [CustomGroup]

    @State private var showingAddReceipt = false
    @State private var editingReceipt: Receipt?
    @State private var viewingReceipt: Receipt?
    @State private var showingSettings = false
    @State private var showingFilters = false
    @State private var showingDashboard = false

    @State private var searchText = ""
    @State private var selectedYear: Int?
    @State private var selectedMonth: Int?
    @State private var selectedCategory: String?
    @State private var selectedGroup: String?

    // Manual multi-select, mirroring `ReceiptList.jsx`'s own approach
    // (plain checkboxes + a Set of selected ids) rather than SwiftUI's
    // `List(selection:)`/`EditMode` machinery — that route hit a real,
    // hard-to-pin-down bug where a row's tap-to-edit `Button` kept firing
    // even while `EditMode` read as `.active` (confirmed via mid-test
    // screenshots showing the Edit form opening instead of the row
    // selecting), regardless of whether `editMode` was read from
    // `@Environment` or an explicitly `.environment()`-bound local
    // `@State`. Fully custom selection state sidesteps that framework
    // interaction entirely and is simple enough not to need it anyway.
    @State private var isSelecting = false
    @State private var selection = Set<PersistentIdentifier>()
    @State private var exportedCSV: ExportedCSV?
    @State private var isUploadingToDrive = false
    @State private var driveUploadSummary: String?

    private var hasActiveFilters: Bool {
        selectedYear != nil || selectedMonth != nil || selectedCategory != nil || selectedGroup != nil || !searchText.isEmpty
    }

    private var filteredReceipts: [Receipt] {
        ReceiptFilter.apply(
            to: receipts,
            year: selectedYear,
            month: selectedMonth,
            category: selectedCategory,
            group: selectedGroup,
            searchText: searchText
        )
    }

    private var availableCategories: [String] {
        CategoryOptions.mergeWithInUseCategories(
            receipts.compactMap(\.category),
            customCategories: customCategories.map(\.name)
        )
    }

    private var availableGroups: [String] {
        GroupOptions.availableGroups(from: receipts, customGroups: customGroups.map(\.name))
    }

    /// True only when every currently-visible (filtered) receipt is
    /// selected — mirrors `ReceiptList.jsx`'s header checkbox, which
    /// selects/clears all currently-loaded rows, not the entire dataset.
    private var isAllFilteredSelected: Bool {
        !filteredReceipts.isEmpty && filteredReceipts.allSatisfy { selection.contains($0.persistentModelID) }
    }

    /// Sum of every receipt (unfiltered by the current search/filter
    /// state — this is a fixed "at a glance" indicator, not scoped to
    /// whatever the list below happens to be showing) dated in the
    /// current calendar month.
    private var thisMonthTotal: Double {
        let calendar = Calendar.current
        let now = Date()
        return receipts
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.totalCost }
    }

    /// One entry per elapsed day of the current month (1...today), summed
    /// from all receipts — feeds the summary card's sparkline.
    private var dailyTotalsThisMonth: [Double] {
        let calendar = Calendar.current
        let now = Date()
        let currentDay = calendar.component(.day, from: now)
        guard currentDay >= 1 else { return [] }
        var totals = [Double](repeating: 0, count: currentDay)
        for receipt in receipts where calendar.isDate(receipt.date, equalTo: now, toGranularity: .month) {
            let day = calendar.component(.day, from: receipt.date)
            if day >= 1 && day <= currentDay {
                totals[day - 1] += receipt.totalCost
            }
        }
        return totals
    }

    /// Per-category totals across ALL receipts (not the current filter
    /// scope), for the quick-filter chip row — categoryless receipts are
    /// excluded since there's no way to express "filter for no category"
    /// through `ReceiptFilter.apply`'s exact-match `category` param, and
    /// the mockup this was ported from doesn't show an uncategorized chip
    /// either.
    private var categoryTotals: [(category: String, total: Double, count: Int)] {
        var totals: [String: (total: Double, count: Int)] = [:]
        for receipt in receipts {
            guard let category = receipt.category, !category.isEmpty else { continue }
            totals[category, default: (0, 0)].total += receipt.totalCost
            totals[category, default: (0, 0)].count += 1
        }
        return totals
            .map { (category: $0.key, total: $0.value.total, count: $0.value.count) }
            .sorted { $0.total > $1.total }
    }

    private var monthSummaryCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("This Month")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(thisMonthTotal, format: .currency(code: "USD"))
                    .font(.title2.bold())
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            let dailyTotals = dailyTotalsThisMonth
            if !dailyTotals.isEmpty {
                let maxTotal = max(dailyTotals.max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(dailyTotals.enumerated()), id: \.offset) { _, total in
                        Capsule()
                            .fill(Color.accentColor.opacity(total > 0 ? 0.8 : 0.25))
                            .frame(width: 4, height: max(4, 36 * (total / maxTotal)))
                    }
                }
                .frame(height: 36)
                .accessibilityHidden(true)
            }
        }
        .padding(16)
        .background(Theme.summaryCardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This month, \(thisMonthTotal.formatted(.currency(code: "USD")))")
    }

    private var categoryChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                CategoryChip(
                    icon: "square.grid.2x2.fill",
                    color: .accentColor,
                    title: "All",
                    subtitle: "\(receipts.count)",
                    isSelected: selectedCategory == nil,
                    action: { selectedCategory = nil }
                )
                .accessibilityIdentifier("categoryChipAll")

                ForEach(categoryTotals, id: \.category) { entry in
                    CategoryChip(
                        icon: CategoryOptions.icon(for: entry.category),
                        color: CategoryOptions.color(for: entry.category),
                        title: entry.category,
                        subtitle: entry.total.formatted(.currency(code: "USD")),
                        isSelected: selectedCategory == entry.category,
                        action: {
                            selectedCategory = (selectedCategory == entry.category) ? nil : entry.category
                        }
                    )
                    .accessibilityIdentifier("categoryChip_\(entry.category)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var receiptListContent: some View {
        if filteredReceipts.isEmpty {
            ContentUnavailableView(
                hasActiveFilters ? "No receipts match the current filters" : "No receipts yet",
                systemImage: "receipt"
            )
        } else {
            List {
                ForEach(filteredReceipts) { receipt in
                    HStack {
                        if isSelecting {
                            Image(systemName: selection.contains(receipt.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(receipt.persistentModelID) ? Color.accentColor : .secondary)
                                .accessibilityIdentifier(selection.contains(receipt.persistentModelID) ? "selectionMarkSelected" : "selectionMarkUnselected")
                        }
                        ReceiptRow(receipt: receipt)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelecting {
                            toggleSelection(receipt.persistentModelID)
                        } else {
                            editingReceipt = receipt
                        }
                    }
                    .accessibilityIdentifier("receiptRow")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteOne(receipt)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        if receipt.imageData != nil {
                            Button {
                                viewingReceipt = receipt
                            } label: {
                                Label("View Receipt", systemImage: "photo")
                            }
                            .tint(.blue)
                            .accessibilityIdentifier("viewReceiptButton")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !receipts.isEmpty {
                    monthSummaryCard
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    categoryChipRow
                        .padding(.vertical, 8)
                }
                receiptListContent
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isSelecting && !selection.isEmpty ? "\(selection.count) Selected" : "Receipt Tracker")
            .searchable(text: $searchText, prompt: "Merchant, description, or amount")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
                ToolbarItem(placement: .navigation) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filter", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("filterButton")
                }
                ToolbarItem(placement: .navigation) {
                    Button {
                        showingDashboard = true
                    } label: {
                        Label("Dashboard", systemImage: "chart.bar")
                    }
                    .accessibilityIdentifier("dashboardButton")
                }
                ToolbarItem(placement: .navigation) {
                    Button {
                        exportCSV(filteredReceipts)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportButton")
                    .disabled(filteredReceipts.isEmpty)
                }
                ToolbarItem(placement: .navigation) {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                    .accessibilityIdentifier("selectButton")
                    .disabled(filteredReceipts.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    // Select All is always shown while isSelecting (not
                    // gated on a non-empty selection like Delete/Export
                    // below) so it's reachable the moment select mode is
                    // entered. This lives in the bottom bar, not the top
                    // navigation bar, because the top bar already has 5
                    // leading items (Settings/Filter/Dashboard/Export/
                    // Select) — a 6th made iOS collapse ALL of them behind
                    // a single "•••" overflow button, hiding Select itself
                    // (confirmed via screenshot).
                    //
                    // Everything below is ONE HStack inside ONE ToolbarItem
                    // — splitting Select All and Delete/Export into two
                    // separate `ToolbarItem(placement: .bottomBar)`s (as an
                    // earlier version of this did) made SwiftUI lay them
                    // out as independent, left-packed toolbar segments:
                    // each `Spacer()` only had effect within its own
                    // segment, so the whole row read as left-aligned
                    // instead of spread across the bar — exactly what the
                    // user's screenshot showed. A single HStack fixes that:
                    // the Spacer competes for the same row's width as
                    // intended.
                    //
                    // The selection COUNT used to live here too, as a
                    // `Text("\(selection.count) selected")` between two
                    // Spacers. That was fragile in two different ways: (1)
                    // with the old, longer "Delete Selected"/"Export
                    // Selected" labels, it got silently squeezed to zero
                    // width and vanished entirely (fixed once by shortening
                    // the labels + `.layoutPriority(1)`); (2) even after
                    // that fix, it disappeared again for odd selection
                    // counts of 3+ specifically (reported by the user,
                    // reproducible: shows for 1/2/4/6, not for 3/5) — a
                    // second, different failure mode in the exact same
                    // crowded HStack, cause not fully understood (not
                    // explained by text width, which is identical for any
                    // single-digit count). Rather than patch this same spot
                    // a third time, the count now lives in the navigation
                    // title instead ("N Selected"), which has dedicated,
                    // uncontested space and isn't competing with Select
                    // All/Delete/Export for room in a single toolbar row.
                    if isSelecting {
                        HStack {
                            Button(isAllFilteredSelected ? "Deselect All" : "Select All") {
                                toggleSelectAll()
                            }
                            .accessibilityIdentifier("selectAllButton")

                            Spacer()

                            if !selection.isEmpty {
                                Button("Delete", role: .destructive) {
                                    deleteSelected()
                                }
                                .accessibilityIdentifier("bulkDeleteButton")
                                Button("Export") {
                                    exportCSV(filteredReceipts.filter { selection.contains($0.persistentModelID) })
                                }
                                .accessibilityIdentifier("bulkExportButton")
                                Button {
                                    uploadSelectedToDrive()
                                } label: {
                                    if isUploadingToDrive {
                                        ProgressView()
                                    } else {
                                        Text("Upload")
                                    }
                                }
                                .disabled(isUploadingToDrive)
                                .accessibilityIdentifier("bulkUploadToDriveButton")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddReceipt = true
                    } label: {
                        Label("Add Receipt", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addReceiptButton")
                }
            }
            .sheet(isPresented: $showingAddReceipt) {
                ReceiptFormView(modelContext: modelContext)
            }
            .sheet(item: $editingReceipt) { receipt in
                ReceiptFormView(modelContext: modelContext, existingReceipt: receipt)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheetView(
                    selectedYear: $selectedYear,
                    selectedMonth: $selectedMonth,
                    selectedCategory: $selectedCategory,
                    availableCategories: availableCategories,
                    selectedGroup: $selectedGroup,
                    availableGroups: availableGroups
                )
            }
            .sheet(isPresented: $showingDashboard) {
                DashboardView()
            }
            .sheet(item: $exportedCSV) { exported in
                ActivityShareSheet(items: [exported.url])
            }
            .fullScreenCover(item: $viewingReceipt) { receipt in
                if let imageData = receipt.imageData {
                    ReceiptImageView(
                        imageData: imageData,
                        uploadFilename: DriveUploadFilename.make(
                            date: receipt.date,
                            merchant: receipt.merchant,
                            fallbackID: String(receipt.persistentModelID.hashValue)
                        )
                    )
                }
            }
            .alert("Google Drive", isPresented: Binding(
                get: { driveUploadSummary != nil },
                set: { isPresented in if !isPresented { driveUploadSummary = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(driveUploadSummary ?? "")
            }
        }
    }

    private func toggleSelection(_ id: PersistentIdentifier) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func toggleSelectAll() {
        if isAllFilteredSelected {
            selection.removeAll()
        } else {
            selection = Set(filteredReceipts.map(\.persistentModelID))
        }
    }

    private func deleteOne(_ receipt: Receipt) {
        modelContext.delete(receipt)
        try? modelContext.save()
    }

    private func deleteSelected() {
        for receipt in filteredReceipts where selection.contains(receipt.persistentModelID) {
            modelContext.delete(receipt)
        }
        try? modelContext.save()
        selection.removeAll()
        isSelecting = false
    }

    private func exportCSV(_ receipts: [Receipt]) {
        let csv = ReceiptCSVExporter.csv(for: receipts)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("receipts-\(UUID().uuidString).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportedCSV = ExportedCSV(url: url)
        } catch {
            // Nothing meaningful to recover into here — export is best-effort;
            // a failed temp-file write would be a device-storage problem, not
            // something this screen can usefully surface differently.
        }
    }

    /// Uploads every selected receipt's photo to Drive independently
    /// (best-effort — see `GoogleDriveUploader.uploadAll`) and shows a
    /// summary alert. Receipts with no attached photo are silently skipped
    /// rather than counted as failures — there's nothing to upload for
    /// them.
    private func uploadSelectedToDrive() {
        guard GoogleDriveAuth.isSignedIn else {
            driveUploadSummary = "Not connected to Google Drive. Connect in Settings first."
            return
        }
        let items: [DriveUploadItem] = filteredReceipts
            .filter { selection.contains($0.persistentModelID) }
            .compactMap { receipt in
                guard let imageData = receipt.imageData else { return nil }
                let filename = DriveUploadFilename.make(
                    date: receipt.date,
                    merchant: receipt.merchant,
                    fallbackID: String(receipt.persistentModelID.hashValue)
                )
                return DriveUploadItem(filename: filename, imageData: imageData)
            }
        guard !items.isEmpty else {
            driveUploadSummary = "None of the selected receipts have a photo to upload."
            return
        }

        isUploadingToDrive = true
        Task {
            do {
                let result = try await GoogleDriveUploader.uploadAll(items)
                driveUploadSummary = result.summary
            } catch {
                driveUploadSummary = error.localizedDescription
            }
            isUploadingToDrive = false
        }
    }
}

private struct CategoryChip: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                    .fill(isSelected ? color.opacity(0.18) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ReceiptRow: View {
    let receipt: Receipt

    private static let dateStyle: Date.FormatStyle = .dateTime.year().month(.twoDigits).day(.twoDigits)

    private var categoryColor: Color { CategoryOptions.color(for: receipt.category) }

    var body: some View {
        HStack(spacing: 0) {
            categoryColor
                .frame(width: 4)

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(categoryColor)
                        .frame(width: 40, height: 40)
                    Image(systemName: CategoryOptions.icon(for: receipt.category))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(receipt.merchant?.isEmpty == false ? receipt.merchant! : "Unknown merchant")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(receipt.totalCost, format: .currency(code: "USD"))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    HStack(spacing: 4) {
                        Text(receipt.date, format: Self.dateStyle)
                            .foregroundStyle(.secondary)
                        if let category = receipt.category, !category.isEmpty {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(category)
                                .foregroundStyle(categoryColor)
                        }
                    }
                    .font(.subheadline)
                    if let description = receipt.itemDescription, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        if let group = receipt.group, !group.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: GroupOptions.icon(for: group))
                                Text(group)
                            }
                            .font(.caption)
                            .foregroundStyle(GroupOptions.color(for: group))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(GroupOptions.color(for: group).opacity(0.16), in: Capsule())
                        }
                        if let note = receipt.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(Theme.notePillForeground)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.notePillBackground, in: Capsule())
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Theme.cardShadowColor, radius: Theme.cardShadowRadius, y: Theme.cardShadowY)
    }
}

/// Wraps the exported CSV's temp-file URL so the export sheet can use
/// `.sheet(item:)` instead of a separate `URL?` + `Bool` pair.
///
/// This was the actual root cause of a real "export sheet shows blank on
/// first tap" bug (reported by the user, confirmed via a mid-test
/// screenshot showing nothing at all — not even `ActivityShareSheet`'s own
/// content). With `.sheet(isPresented:)` bound to one `@State` bool and the
/// URL held in a SEPARATE `@State` optional set in the same function call,
/// the sheet's content closure could be evaluated with the URL still nil
/// on the very first presentation — rendering nothing, since `if let
/// csvExportURL { ... }` produces no view at all when it's nil. `viewingReceipt`/
/// `editingReceipt` above already use `.sheet(item:)`/`.fullScreenCover(item:)`
/// correctly for exactly this reason; the export flow was the one sheet in
/// this file that didn't follow that pattern. Never go back to a
/// `Bool` + separately-set-optional pair for sheet content in this app —
/// always tie the optional itself to `.sheet(item:)`.
private struct ExportedCSV: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    ReceiptListView()
        .modelContainer(for: Receipt.self, inMemory: true)
}
