import SwiftUI
import SwiftData
import PhotosUI

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
    @State private var showingPDFWarning = false
    @State private var pendingPDFURL: URL?
    @State private var isExtracting = false
    @State private var extractNotice: String?
    @State private var showingFullImage = false

    /// Holds every receipt OCR detected in the attached photo (not just the
    /// first) so Save can walk through them one at a time — ports the web
    /// app's `UploadReceipt.jsx` review queue ("Receipt X of N"). Only
    /// meaningful in create mode (`existingReceipt == nil`); a photo
    /// replaced during edit stays first-only + notice, matching
    /// `ReceiptForm.jsx`'s rescan-on-replace behavior (the queue only
    /// exists in the web app's separate upload flow, never in edit).
    @State private var reviewQueue: [ExtractedReceipt] = []
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
                            Text("Scanning receipt…")
                        }
                    }
                    if let extractNotice {
                        Text(extractNotice)
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    if isReviewingQueue {
                        Text("Found \(reviewQueue.count) receipts in this photo — reviewing receipt \(reviewIndex + 1) of \(reviewQueue.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("queueStatusText")
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
                Button("Import PDF") { showingDocumentPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingDocumentPicker) {
                PDFDocumentPickerView(
                    onPick: { url in
                        showingDocumentPicker = false
                        pendingPDFURL = url
                        showingPDFWarning = true
                    },
                    onCancel: { showingDocumentPicker = false }
                )
            }
            .alert("Scan This PDF?", isPresented: $showingPDFWarning) {
                Button("Cancel", role: .cancel) { pendingPDFURL = nil }
                Button("Continue") { processPendingPDF() }
            } message: {
                Text("Up to \(PDFPageRenderer.maxPages) pages will be scanned together as one import. If they contain more than one receipt, you'll review each one before saving.")
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
                if let imageData {
                    ReceiptImageView(
                        imageData: imageData,
                        uploadFilename: DriveUploadFilename.make(date: date, merchant: merchant, fallbackID: "draft")
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

    private func handlePickedImage(_ image: UIImage) {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else { return }
        imageData = jpegData
        Task { await scanReceipt(images: [jpegData]) }
    }

    /// Renders every page of the imported PDF (up to `PDFPageRenderer.maxPages`)
    /// and sends them all to OCR together — the model decides whether they're
    /// one receipt spanning multiple pages or several separate receipts (see
    /// `AnthropicVisionClient`'s doc comment). Only the FIRST
    /// page becomes the receipt's stored/displayed photo — this app has no
    /// concept of multiple photos per receipt, and every already-queued
    /// receipt from one photo already shares that one photo today (see
    /// `advanceToNextInQueue`, which never resets `imageData`), so this isn't
    /// a new inconsistency.
    private func processPendingPDF() {
        guard let url = pendingPDFURL else { return }
        pendingPDFURL = nil
        let pages = PDFPageRenderer.renderPages(of: url)
        guard let firstPage = pages.first, let firstJPEG = firstPage.jpegData(compressionQuality: 0.8) else {
            extractNotice = "Couldn't read that PDF — please check the fields below."
            return
        }
        imageData = firstJPEG
        let allJPEGs = pages.compactMap { $0.jpegData(compressionQuality: 0.8) }
        Task { await scanReceipt(images: allJPEGs) }
    }

    /// Attaching or replacing a photo always re-runs OCR and overwrites
    /// date/merchant/totalCost/description with the result — intentionally
    /// destructive during edit, mirroring `ReceiptForm.jsx`'s documented
    /// v1.3 design decision (the new photo's OCR result is authoritative,
    /// no merge/confirm prompt). Does not touch `imageData` itself (already
    /// set by the caller) or anything outside these four fields.
    ///
    /// In create mode, N > 1 detected receipts (whether from one photo with
    /// multiple receipts in frame, or a multi-page PDF the model decided
    /// contains separate receipts) starts a review queue
    /// (`reviewQueue`/`reviewIndex`) instead of silently discarding
    /// receipts 2..N — see `save()`/`advanceToNextInQueue()`. In edit mode
    /// the queue is never populated (`isReviewingQueue` is gated on
    /// `existingReceipt == nil`), matching the web app where the queue only
    /// exists in the separate upload flow, never in edit.
    private func scanReceipt(images: [Data]) async {
        isExtracting = true
        extractNotice = nil
        errorMessage = nil
        reviewQueue = []
        reviewIndex = 0
        defer { isExtracting = false }

        do {
            let receipts = try await ReceiptExtractor.extractReceipts(images: images, mediaType: "image/jpeg")
            guard let first = receipts.first else {
                extractNotice = "No receipt details were detected — please check the fields below."
                return
            }
            applyExtractedReceipt(first)
            if existingReceipt == nil, receipts.count > 1 {
                reviewQueue = receipts
                reviewIndex = 0
            }
        } catch {
            extractNotice = "Automatic scanning failed (\(error.localizedDescription)) — please check the fields below."
        }
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
        applyExtractedReceipt(reviewQueue[reviewIndex])
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
                imageData: imageData
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
