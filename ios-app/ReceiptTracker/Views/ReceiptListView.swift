import SwiftUI
import SwiftData

struct ReceiptListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

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

    private var hasActiveFilters: Bool {
        selectedYear != nil || selectedMonth != nil || selectedCategory != nil || !searchText.isEmpty
    }

    private var filteredReceipts: [Receipt] {
        ReceiptFilter.apply(
            to: receipts,
            year: selectedYear,
            month: selectedMonth,
            category: selectedCategory,
            searchText: searchText
        )
    }

    private var availableCategories: [String] {
        CategoryOptions.mergeWithInUseCategories(receipts.compactMap(\.category))
    }

    /// True only when every currently-visible (filtered) receipt is
    /// selected — mirrors `ReceiptList.jsx`'s header checkbox, which
    /// selects/clears all currently-loaded rows, not the entire dataset.
    private var isAllFilteredSelected: Bool {
        !filteredReceipts.isEmpty && filteredReceipts.allSatisfy { selection.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            Group {
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
                }
            }
            .navigationTitle("Receipt Tracker")
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
                    // segment, so the "N selected" text (with nothing after
                    // it to push against) ended up squeezed to zero width
                    // and never appeared, and the whole row read as
                    // left-aligned instead of spread across the bar —
                    // exactly what the user's screenshot showed. A single
                    // HStack fixes both: the Spacers now compete for the
                    // same row's width as intended.
                    if isSelecting {
                        HStack {
                            Button(isAllFilteredSelected ? "Deselect All" : "Select All") {
                                toggleSelectAll()
                            }
                            .accessibilityIdentifier("selectAllButton")

                            if !selection.isEmpty {
                                Spacer()
                                // Fitting "Deselect All" + count + both action
                                // buttons on one bottom-bar row is tight —
                                // with the full "Delete Selected"/"Export
                                // Selected" labels, this Text got squeezed
                                // out of the layout entirely (confirmed via
                                // screenshot: buttons stayed, the count text
                                // silently vanished, no truncation/ellipsis,
                                // just gone). Shortened the two action labels
                                // and gave this Text priority so it's never
                                // the one sacrificed if space is tight again.
                                Text("\(selection.count) selected")
                                    .layoutPriority(1)
                                Spacer()
                                Button("Delete", role: .destructive) {
                                    deleteSelected()
                                }
                                .accessibilityIdentifier("bulkDeleteButton")
                                Button("Export") {
                                    exportCSV(filteredReceipts.filter { selection.contains($0.persistentModelID) })
                                }
                                .accessibilityIdentifier("bulkExportButton")
                            } else {
                                Spacer()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddReceipt = true
                    } label: {
                        Label("Add Receipt", systemImage: "plus")
                    }
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
                    availableCategories: availableCategories
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
                    ReceiptImageView(imageData: imageData)
                }
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
}

private struct ReceiptRow: View {
    let receipt: Receipt

    private static let dateStyle: Date.FormatStyle = .dateTime.year().month(.twoDigits).day(.twoDigits)

    var body: some View {
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
            HStack {
                Text(receipt.date, format: Self.dateStyle)
                if let category = receipt.category, !category.isEmpty {
                    Text("· \(category)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let description = receipt.itemDescription, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let note = receipt.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
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
