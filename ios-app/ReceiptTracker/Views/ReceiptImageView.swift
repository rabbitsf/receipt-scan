import SwiftUI
import UIKit
import PDFKit

/// Full-size, unconstrained receipt photo viewer — ports the web app's
/// image modal (`ReceiptList.jsx`'s "View Receipt" button, Section 3.8:
/// no 240px thumbnail cap, shows the image at full size). Presented as a
/// full-screen cover from both the receipt list (per-row) and the form
/// (tapping the attached-photo thumbnail).
///
/// "Save to Photos" is the native equivalent of the web app's "Download
/// Photo" button (v1.2.1) — there's no filesystem download concept on iOS;
/// saving the already-on-device image into the user's Photos library is the
/// closest match to "get a copy of this outside the app".
///
/// A receipt that came from a PDF shows all of its pages instead, with Share
/// (Save to Files, AirDrop, …) in place of "Save to Photos".
struct ReceiptImageView: View {
    let imageData: Data?
    var pdfData: Data? = nil
    /// What "Upload to Drive" sends (`DriveUploadItem.forReceipt`). Real
    /// call sites pass the receipt's date/merchant for a meaningful name.
    var driveItem: DriveUploadItem? = nil

    @State private var shareURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var statusMessage: String?
    @State private var isUploadingToDrive = false

    // Pinch-to-zoom + pan. A plain ScrollView (the previous implementation)
    // never responds to a pinch gesture on its own — it only scrolls
    // content that's already larger than the viewport. Zoom has to be
    // implemented explicitly via MagnificationGesture driving a
    // `.scaleEffect`, with a DragGesture for panning once zoomed in.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Explicit background fill, not a `.background()`
                    // modifier on the GeometryReader — keeps the black
                    // fill guaranteed to cover the full viewport regardless
                    // of how the image content inside sizes itself.
                    Color.black

                    if let pdfData {
                        ReceiptPDFView(data: pdfData)
                            .accessibilityIdentifier("receiptPDFView")
                    } else if let imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            // An EXACT frame (not maxWidth/maxHeight, which
                            // only cap growth without forcing it) is what
                            // actually makes a resizable+scaledToFit image
                            // fill the available space — using max-only
                            // constraints here previously left the image
                            // rendering at an effectively invisible size
                            // (confirmed via screenshot: totally blank,
                            // not even the black background showing).
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(scale)
                            .offset(offset)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("receiptFullImage")
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = min(max(lastScale * value, minScale), maxScale)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        if scale == minScale {
                                            offset = .zero
                                            lastOffset = .zero
                                        } else {
                                            offset = clampedOffset(offset, in: geometry.size)
                                            lastOffset = offset
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        guard scale > minScale else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        guard scale > minScale else { return }
                                        offset = clampedOffset(offset, in: geometry.size)
                                        lastOffset = offset
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if scale > minScale {
                                        scale = minScale
                                        offset = .zero
                                    } else {
                                        scale = 2.5
                                        offset = .zero
                                    }
                                    lastScale = scale
                                    lastOffset = offset
                                }
                            }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(pdfData == nil ? "Receipt Photo" : "Receipt PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("closeReceiptImageButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if pdfData != nil {
                        if let shareURL {
                            ShareLink(item: shareURL) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityIdentifier("sharePDFButton")
                        }
                    } else {
                        Button {
                            saveToPhotos()
                        } label: {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                        .accessibilityIdentifier("savePhotoButton")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        uploadToDrive()
                    } label: {
                        if isUploadingToDrive {
                            ProgressView()
                        } else {
                            Label("Upload to Drive", systemImage: "arrow.up.doc")
                        }
                    }
                    .disabled(isUploadingToDrive)
                    .accessibilityIdentifier("uploadToDriveButton")
                }
            }
            .onAppear(perform: writeShareFile)
            .safeAreaInset(edge: .bottom) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                        .accessibilityIdentifier("imageActionStatus")
                }
            }
        }
    }

    /// Keeps the panned image from being dragged entirely off-screen —
    /// clamps to how far the scaled image actually overhangs the viewport
    /// on each axis (zero overhang once back at `minScale`).
    private func clampedOffset(_ proposed: CGSize, in viewportSize: CGSize) -> CGSize {
        let maxX = max(0, (viewportSize.width * (scale - 1)) / 2)
        let maxY = max(0, (viewportSize.height * (scale - 1)) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private var uploadItem: DriveUploadItem? {
        driveItem ?? DriveUploadItem.forReceipt(date: Date(), merchant: nil, fallbackID: UUID().uuidString, imageData: imageData, pdfData: pdfData)
    }

    /// ShareLink needs a file; name it like the Drive upload.
    private func writeShareFile() {
        guard let pdfData, shareURL == nil else { return }
        let name = uploadItem?.filename ?? "Receipt.pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if (try? pdfData.write(to: url)) != nil { shareURL = url }
    }

    private func saveToPhotos() {
        guard let imageData, let uiImage = UIImage(data: imageData) else { return }
        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
        statusMessage = "Saved to Photos"
    }

    private func uploadToDrive() {
        guard GoogleDriveAuth.isSignedIn else {
            statusMessage = "Not connected to Google Drive. Connect in Settings first."
            return
        }
        isUploadingToDrive = true
        statusMessage = nil
        Task {
            do {
                guard let uploadItem else { throw GoogleDriveUploadError.invalidResponse }
                try await GoogleDriveUploader.uploadOne(uploadItem)
                statusMessage = "Uploaded to Google Drive"
            } catch {
                statusMessage = error.localizedDescription
            }
            isUploadingToDrive = false
        }
    }
}

/// All pages of a receipt PDF, scrollable and zoomable (PDFKit).
struct ReceiptPDFView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

#Preview {
    ReceiptImageView(imageData: Data())
}
