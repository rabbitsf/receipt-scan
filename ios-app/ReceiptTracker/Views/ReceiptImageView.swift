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

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("receiptFullImage")
                }
            }
            .background(Color.black)
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

    private func saveToPhotos() {
        guard let uiImage = UIImage(data: imageData) else { return }
        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
        saveStatusMessage = "Saved to Photos"
    }
}

#Preview {
    ReceiptImageView(imageData: Data())
}
