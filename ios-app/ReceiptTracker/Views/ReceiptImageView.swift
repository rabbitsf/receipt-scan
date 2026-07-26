import SwiftUI
import UIKit

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
struct ReceiptImageView: View {
    let imageData: Data
    @Environment(\.dismiss) private var dismiss
    @State private var saveStatusMessage: String?

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

                    if let uiImage = UIImage(data: imageData) {
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
            .navigationTitle("Receipt Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("closeReceiptImageButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveToPhotos()
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("savePhotoButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let saveStatusMessage {
                    Text(saveStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                        .accessibilityIdentifier("savePhotoStatus")
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

    private func saveToPhotos() {
        guard let uiImage = UIImage(data: imageData) else { return }
        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
        saveStatusMessage = "Saved to Photos"
    }
}

#Preview {
    ReceiptImageView(imageData: Data())
}
