import SwiftUI
import SwiftData
import PhotosUI
import PDFKit

/// ONE form reused for both manual-add and edit (mirrors the web app's
/// `ReceiptForm.jsx` convention — never fork a second form for edit).
/// `existingReceipt == nil` means create mode; non-nil means edit mode,
/// initialized from that receipt's current values. Editing mutates local
/// `@State` copies only — nothing writes back to the model until Save is
/// tapped, so Cancel always discards changes cleanly.
struct ReceiptFormView: View {
    let modelContext: ModelContext
    let existingReceipt: Receipt?

    @Environment(\.dismiss) private var dismiss
    @Query private var allReceipts: [Receipt]
    @Query(sort: \CustomCategory.name) private var customCategories: [CustomCategory]
    @Query(sort: \CustomGroup.name) private var customGroups: [CustomGroup]

    @State private var date: Date
    @State private var merchant: String
    @State private var totalCost: String
    @State private var description: String
    @State private var imageData: Data?
    /// The receipt's own pages when it came from a PDF (see `Receipt.pdfData`).
    @State private var pdfData: Data?
    @State private var errorMessage: String?

    @State private var categorySelection: String?
    @State private var isCustomCategoryMode: Bool
    @State private var customCategoryText: String
    @State private var groupSelection: String?
    @State private var isCustomGroupMode: Bool
    @State private var customGroupText: String
    @State private var note: String

    @State private var showingPhotoSourceDialog = false
    @State private var showingCamera = false
    @State private var showingLibraryPicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingDocumentPicker = false
    /// What to run once the user answers the AI permission prompt.
    @State private var consentRequest: (provider: OCRProvider, onAllow: () -> Void, onDeny: () -> Void)?
    @State private var pendingPDFFiles: [PDFImportScanner.File] = []
    @State private var pendingCost: PDFImportScanner.CostSummary?
    @State private var showingCostPrompt = false
    @State private var isExtracting = false
    @State private var scanProgress: String?
    @State private var extractNotice: String?
    /// Where the current entry came from and its warnings (PDF imports).
    @State private var sourceLabel: String?
    @State private var itemNotices: [String] = []
    @State private var showingFullImage = false

    /// Holds every receipt OCR detected in the attached photo (not just the
    /// first) so Save can walk through them one at a time — ports the web
    /// app's `UploadReceipt.jsx` review queue ("Receipt X of N"). Only
    /// meaningful in create mode (`existingReceipt == nil`); a photo
    /// replaced during edit stays first-only + notice, matching
    /// `ReceiptForm.jsx`'s rescan-on-replace behavior (the queue only
    /// exists in the web app's separate upload flow, never in edit).
    @State private var reviewQueue: [ScanReviewItem] = []
    @State private var reviewIndex = 0

    private var isReviewingQueue: Bool {
        existingReceipt == nil && reviewQueue.count > 1
    }

    private var isLastInQueue: Bool {
        reviewIndex + 1 >= reviewQueue.count
    }

    private var saveButtonLabel: String {
        isReviewingQueue && !isLastInQueue ? "Save & Review Next" : "Save"
    }

    private var availableCategories: [String] {
        CategoryOptions.mergeWithInUseCategories(
            allReceipts.compactMap(\.category),
            customCategories: customCategories.map(\.name)
        )
    }

    /// Bridges the Picker's selection (which includes the transient
    /// `customSentinel` option) to `categorySelection`/`isCustomCategoryMode`.
    private var categoryPickerBinding: Binding<String?> {
        Binding(
            get: { isCustomCategoryMode ? CategoryOptions.customSentinel : categorySelection },
            set: { newValue in
                if newValue == CategoryOptions.customSentinel {
                    isCustomCategoryMode = true
                    customCategoryText = ""
                } else {
                    isCustomCategoryMode = false
                    categorySelection = newValue
                }
            }
        )
    }

    /// Resolved category value to persist — the custom text field if in
    /// custom mode, otherwise whatever's picked (nil = no category).
    private var resolvedCategory: String? {
        if isCustomCategoryMode {
            let trimmed = customCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return categorySelection
    }

    private var availableGroups: [String] {
        GroupOptions.availableGroups(from: allReceipts, customGroups: customGroups.map(\.name))
    }

    /// Bridges the Group picker's selection to
    /// `groupSelection`/`isCustomGroupMode`, same shape as
    /// `categoryPickerBinding`.
    private var groupPickerBinding: Binding<String?> {
        Binding(
            get: { isCustomGroupMode ? GroupOptions.customSentinel : groupSelection },
            set: { newValue in
                if newValue == GroupOptions.customSentinel {
                    isCustomGroupMode = true
                    customGroupText = ""
                } else {
                    isCustomGroupMode = false
                    groupSelection = newValue
                }
            }
        )
    }

    /// Resolved group value to persist, mirroring `resolvedCategory`.
    private var resolvedGroup: String? {
        if isCustomGroupMode {
            let trimmed = customGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return groupSelection
    }

    init(modelContext: ModelContext, existingReceipt: Receipt? = nil) {
        self.modelContext = modelContext
        self.existingReceipt = existingReceipt
        _date = State(initialValue: existingReceipt?.date ?? Date())
        _merchant = State(initialValue: existingReceipt?.merchant ?? "")
        _totalCost = State(initialValue: existingReceipt.map { String($0.totalCost) } ?? "")
        _description = State(initialValue: existingReceipt?.itemDescription ?? "")
        _imageData = State(initialValue: existingReceipt?.imageData)
        _pdfData = State(initialValue: existingReceipt?.pdfData)
        _note = State(initialValue: existingReceipt?.note ?? "")

        // Uses the STATIC predefined list only for this synchronous check
        // (in-use custom categories aren't known yet at init time — the
        // `@Query`-backed `availableCategories` isn't available until the
        // view body evaluates). If the existing category later turns out
        // to already be in the merged list, that's fine — it just stays
        // in custom mode with the same text pre-filled, still correct.
        let existingCategory = existingReceipt?.category
        let isKnownPredefined = existingCategory.map { CategoryOptions.predefined.contains($0) } ?? true
        _isCustomCategoryMode = State(initialValue: existingCategory != nil && !isKnownPredefined)
        _categorySelection = State(initialValue: isKnownPredefined ? existingCategory : nil)
        _customCategoryText = State(initialValue: isKnownPredefined ? "" : (existingCategory ?? ""))

        // Group has no predefined list to check synchronously against
        // (unlike Category above), so an existing group always starts in
        // custom mode with its value pre-filled — correct regardless of
        // `@Query`-backed `availableGroups` not being ready yet at init
        // time, and simpler than Category's predefined-membership check
        // since there's nothing to check membership against.
        let existingGroup = existingReceipt?.group
        _isCustomGroupMode = State(initialValue: existingGroup != nil)
        _groupSelection = State(initialValue: nil)
        _customGroupText = State(initialValue: existingGroup ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let imageData, let uiImage = UIImage(data: imageData) {
                        Button {
                            showingFullImage = true
                        } label: {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 240)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("viewFullImageButton")
                    }

                    if let pdfPageCount {
                        Label("PDF · \(pdfPageCount) page\(pdfPageCount == 1 ? "" : "s")", systemImage: "doc.richtext")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("pdfBadge")
                    }

                    Button {
                        showingPhotoSourceDialog = true
                    } label: {
                        Label(imageData == nil ? "Attach a photo (optional)" : "Replace photo", systemImage: "camera.fill")
                    }
                    .accessibilityIdentifier("attachPhotoButton")
                    .disabled(isExtracting)

                    if isExtracting {
                        HStack {
                            ProgressView()
                            Text(scanProgress ?? "Scanning receipt…")
                        }
                    }
                    if let extractNotice {
                        Text(extractNotice)
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    if isReviewingQueue {
                        Text("Found \(reviewQueue.count) receipts — reviewing receipt \(reviewIndex + 1) of \(reviewQueue.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("queueStatusText")
                    }
                    if let sourceLabel {
                        Text(sourceLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("sourceLabelText")
                    }
                    ForEach(itemNotices, id: \.self) { notice in
                        Text(notice)
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }

                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Merchant", text: $merchant)
                    .accessibilityIdentifier("merchantField")
                TextField("Total Cost", text: $totalCost)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("totalCostField")
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)

                Section {
                    Picker("Category", selection: categoryPickerBinding) {
                        Text("— Select category —").tag(String?.none)
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category).tag(String?.some(category))
                        }
                        Text("Custom category…").tag(String?.some(CategoryOptions.customSentinel))
                    }
                    .accessibilityIdentifier("categoryPicker")

                    if isCustomCategoryMode {
                        TextField("Custom category", text: $customCategoryText)
                            .accessibilityIdentifier("customCategoryField")
                    }
                }

                Section {
                    Picker("Group", selection: groupPickerBinding) {
                        Text("— No group —").tag(String?.none)
                        ForEach(availableGroups, id: \.self) { group in
                            Text(group).tag(String?.some(group))
                        }
                        Text("New group…").tag(String?.some(GroupOptions.customSentinel))
                    }
                    .accessibilityIdentifier("groupPicker")

                    if isCustomGroupMode {
                        TextField("Group name", text: $customGroupText)
                            .accessibilityIdentifier("customGroupField")
                    }
                }

                Section {
                    TextField("Note (personal, never auto-filled)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("noteField")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle(existingReceipt == nil ? "Add Receipt" : "Edit Receipt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonLabel) { save() }
                        .disabled(merchant.isEmpty || totalCost.isEmpty || isExtracting)
                        .accessibilityIdentifier("saveReceiptButton")
                }
            }
            .confirmationDialog("Add Photo", isPresented: $showingPhotoSourceDialog) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showingCamera = true }
                }
                // A plain Button that flips a separate @State bool, NOT a
                // PhotosPicker embedded directly as a dialog row — the
                // latter silently fails to present its sheet because the
                // dialog's own dismissal animation conflicts with the
                // picker trying to present at the same time.
                Button("Choose from Library") { showingLibraryPicker = true }
                Button("Import PDF") {
                    // UI tests can't drive the system file picker reliably (same
                    // reason as the photo seed in `ReceiptTrackerApp`); they point
                    // this test-only variable at a folder of PDFs instead.
                    if let dir = ProcessInfo.processInfo.environment["UITEST_PDF_IMPORT_DIR"] {
                        let urls = ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? [])
                            .filter { $0.pathExtension == "pdf" }
                            .sorted { $0.lastPathComponent < $1.lastPathComponent }
                        preparePDFImport(urls)
                    } else {
                        showingDocumentPicker = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingDocumentPicker) {
                PDFDocumentPickerView(
                    allowsMultipleSelection: existingReceipt == nil,
                    onPick: { urls in
                        showingDocumentPicker = false
                        preparePDFImport(urls)
                    },
                    onCancel: { showingDocumentPicker = false }
                )
            }
            .alert(costPromptTitle, isPresented: $showingCostPrompt, presenting: pendingCost) { cost in
                Button("Scan All \(cost.totalPages) Pages (\(costText(cost.allPagesUSD)))") { runPDFScan(.allPages) }
                    .accessibilityIdentifier("scanAllPagesButton")
                if cost.quickScanPages < cost.totalPages {
                    Button("Scan First \(PDFPageRenderer.quickScanPages) Pages\(pendingPDFFiles.count > 1 ? " of Each" : "") (\(costText(cost.quickScanUSD)))") {
                        runPDFScan(.firstPages(PDFPageRenderer.quickScanPages))
                    }
                    .accessibilityIdentifier("scanFirstPagesButton")
                }
                Button("Cancel", role: .cancel) { pendingPDFFiles = [] }
            } message: { cost in
                Text(costPromptMessage(cost))
            }
            .alert(
                consentRequest.map { "Send Receipts to \($0.provider.displayName)?" } ?? "",
                isPresented: Binding(get: { consentRequest != nil }, set: { if !$0 { consentRequest = nil } }),
                presenting: consentRequest
            ) { request in
                Button("Don't Allow", role: .cancel) {
                    consentRequest = nil
                    request.onDeny()
                }
                Button("Allow") {
                    AIScanConsent.set(true, for: request.provider)
                    consentRequest = nil
                    // Let this alert finish closing first; a second alert
                    // (the PDF cost prompt) presented mid-dismissal is dropped.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { request.onAllow() }
                }
                .accessibilityIdentifier("allowAIScanButton")
            } message: { request in
                Text(AIScanConsent.explanation(for: request.provider))
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCaptureView(
                    onCapture: { image in
                        showingCamera = false
                        handlePickedImage(image)
                    },
                    onCancel: { showingCamera = false }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingLibraryPicker, selection: $photoPickerItem, matching: .images)
            .fullScreenCover(isPresented: $showingFullImage) {
                if imageData != nil || pdfData != nil {
                    ReceiptImageView(
                        imageData: imageData,
                        pdfData: pdfData,
                        driveItem: DriveUploadItem.forReceipt(date: date, merchant: merchant, fallbackID: "draft", imageData: imageData, pdfData: pdfData)
                    )
                }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        handlePickedImage(image)
                    }
                    photoPickerItem = nil
                }
            }
        }
    }

    private var pdfPageCount: Int? {
        pdfData.flatMap { PDFDocument(data: $0)?.pageCount }
    }

    /// A camera/library photo replaces any PDF the receipt had.
    private func handlePickedImage(_ image: UIImage) {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else { return }
        imageData = jpegData
        pdfData = nil
        sourceLabel = nil
        itemNotices = []
        withScanPermission(
            onAllow: { Task { await scanReceipt(images: [jpegData]) } },
            onDeny: { extractNotice = "Scanning is off for this photo — please enter the details below." }
        )
    }

    /// Asks once per provider before any receipt is sent to an AI service
    /// (`AIScanConsent`). Without a saved key nothing would be sent anyway,
    /// so the scan goes ahead and reports the missing key instead.
    private func withScanPermission(onAllow: @escaping () -> Void, onDeny: @escaping () -> Void) {
        let provider = OCRSettings.selectedProvider()
        if AIScanConsent.isGranted(for: provider) || APIKeyStore.load(for: provider)?.isEmpty != false {
            onAllow()
        } else {
            consentRequest = (provider, onAllow, onDeny)
        }
    }

    // MARK: - PDF import

    private func preparePDFImport(_ urls: [URL]) {
        withScanPermission(
            onAllow: { showCostPrompt(for: urls) },
            onDeny: { extractNotice = "PDF import needs permission to send pages for scanning. You can allow it in Settings → Receipt Scanning." }
        )
    }

    private func showCostPrompt(for urls: [URL]) {
        let picked = existingReceipt == nil ? urls : Array(urls.prefix(1))
        pendingPDFFiles = picked.compactMap { url in
            (try? Data(contentsOf: url)).map { PDFImportScanner.File(name: url.lastPathComponent, data: $0) }
        }
        guard !pendingPDFFiles.isEmpty else {
            extractNotice = "Couldn't open that file — please check the fields below."
            return
        }
        let provider = OCRSettings.selectedProvider()
        pendingCost = PDFImportScanner.costSummary(files: pendingPDFFiles, provider: provider, model: OCRSettings.effectiveModel(for: provider))
        showingCostPrompt = true
    }

    private var costPromptTitle: String {
        pendingPDFFiles.count > 1 ? "Scan \(pendingPDFFiles.count) PDFs?" : "Scan This PDF?"
    }

    private func costText(_ usd: Double?) -> String {
        usd.map(OCRScanCost.formatted) ?? "cost unknown"
    }

    private func costPromptMessage(_ cost: PDFImportScanner.CostSummary) -> String {
        var lines = cost.files.map { "\($0.name) — \($0.pages) page\($0.pages == 1 ? "" : "s")" }
        let provider = OCRSettings.selectedProvider()
        if cost.allPagesUSD == nil {
            lines.append("The cost can't be estimated for the custom model \(OCRSettings.effectiveModel(for: provider)).")
        } else {
            lines.append("Estimated \(provider.displayName) cost is shown on each button. Each file is scanned on its own; you'll review every receipt found before saving.")
        }
        return lines.joined(separator: "\n")
    }

    private func runPDFScan(_ scope: PDFImportScanner.Scope) {
        let files = pendingPDFFiles
        pendingPDFFiles = []
        let provider = OCRSettings.selectedProvider()
        isExtracting = true
        extractNotice = nil
        errorMessage = nil
        Task {
            let items = await PDFImportScanner.scan(
                files: files,
                scope: scope,
                provider: provider,
                extract: { try await ReceiptExtractor.extractReceipts(images: $0, mediaType: "image/jpeg", provider: provider) },
                progress: { number, count in
                    await MainActor.run { scanProgress = count > 1 ? "Scanning file \(number) of \(count)…" : nil }
                }
            )
            scanProgress = nil
            isExtracting = false
            applyReviewItems(items)
        }
    }

    // MARK: - Scanning and the review queue

    /// Attaching or replacing a photo always re-runs OCR and overwrites
    /// date/merchant/totalCost/description with the result — intentionally
    /// destructive during edit, mirroring `ReceiptForm.jsx`'s documented
    /// v1.3 design decision. In create mode, N > 1 detected receipts start a
    /// review queue (`reviewQueue`/`reviewIndex`) — see `save()` /
    /// `advanceToNextInQueue()`. In edit mode only the first is used.
    private func scanReceipt(images: [Data]) async {
        isExtracting = true
        extractNotice = nil
        errorMessage = nil
        defer { isExtracting = false }

        do {
            let receipts = try await ReceiptExtractor.extractReceipts(images: images, mediaType: "image/jpeg")
            guard !receipts.isEmpty else {
                extractNotice = "No receipt details were detected — please check the fields below."
                return
            }
            applyReviewItems(receipts.map { ScanReviewItem(fields: $0, imageData: imageData, pdfData: nil) })
        } catch {
            extractNotice = "Automatic scanning failed (\(error.localizedDescription)) — please check the fields below."
        }
    }

    private func applyReviewItems(_ items: [ScanReviewItem]) {
        reviewQueue = []
        reviewIndex = 0
        guard let first = items.first else { return }
        applyReviewItem(first)
        if existingReceipt == nil, items.count > 1 {
            reviewQueue = items
        } else if items.count > 1 {
            extractNotice = "Found \(items.count) receipts; the fields were filled in from the first. Add the others as separate receipts."
        }
    }

    private func applyReviewItem(_ item: ScanReviewItem) {
        if let fields = item.fields {
            applyExtractedReceipt(fields)
        } else if existingReceipt == nil {
            date = Date()
            merchant = ""
            totalCost = ""
            description = ""
        }
        imageData = item.imageData ?? imageData
        pdfData = item.pdfData
        sourceLabel = item.sourceLabel
        itemNotices = item.notices
    }

    private func applyExtractedReceipt(_ extracted: ExtractedReceipt) {
        if let parsedDate = Self.parseOCRDate(extracted.date) {
            date = parsedDate
        }
        merchant = extracted.merchant
        totalCost = String(extracted.totalCost)
        description = extracted.description
    }

    /// Exposed for unit testing without needing a `ReceiptFormView` instance.
    /// Local-time parsing (never UTC) lives in `DateOnly`.
    static func parseOCRDate(_ string: String) -> Date? {
        DateOnly.date(from: string)
    }

    /// Saves the current item, then moves to the next detected receipt in
    /// the queue (same photo, blank category/note — each is a distinct
    /// physical receipt) rather than dismissing. Category/note are
    /// per-receipt and OCR never populates them, so they reset here exactly
    /// like a fresh manual entry would.
    private func advanceToNextInQueue() {
        reviewIndex += 1
        applyReviewItem(reviewQueue[reviewIndex])
        categorySelection = nil
        isCustomCategoryMode = false
        customCategoryText = ""
        groupSelection = nil
        isCustomGroupMode = false
        customGroupText = ""
        note = ""
        errorMessage = nil
    }

    private func save() {
        guard let cost = Double(totalCost) else {
            errorMessage = "Total cost must be a number."
            return
        }
        let trimmedDescription = description.isEmpty ? nil : description
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteToSave = trimmedNote.isEmpty ? nil : trimmedNote

        if let existingReceipt {
            existingReceipt.date = date
            existingReceipt.totalCost = cost
            existingReceipt.merchant = merchant
            existingReceipt.itemDescription = trimmedDescription
            existingReceipt.imageData = imageData
            existingReceipt.pdfData = pdfData
            existingReceipt.category = resolvedCategory
            existingReceipt.group = resolvedGroup
            existingReceipt.note = noteToSave
            existingReceipt.updatedAt = Date()
        } else {
            let receipt = Receipt(
                date: date,
                totalCost: cost,
                merchant: merchant,
                itemDescription: trimmedDescription,
                category: resolvedCategory,
                group: resolvedGroup,
                note: noteToSave,
                imageData: imageData,
                pdfData: pdfData
            )
            modelContext.insert(receipt)
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        if isReviewingQueue, !isLastInQueue {
            advanceToNextInQueue()
        } else {
            dismiss()
        }
    }
}

#Preview {
    ReceiptFormView(modelContext: try! ModelContainer(for: Receipt.self).mainContext)
}
