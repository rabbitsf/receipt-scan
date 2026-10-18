import SwiftUI
import UniformTypeIdentifiers

/// Mirrors `CameraCaptureView.swift`'s `UIViewControllerRepresentable` +
/// `Coordinator` + closure-callback pattern, wrapping
/// `UIDocumentPickerViewController` instead of `UIImagePickerController`.
struct PDFDocumentPickerView: UIViewControllerRepresentable {
    /// Several files at once when adding receipts; one when editing.
    var allowsMultipleSelection = false
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // `asCopy: true` means the URL handed to the delegate is already a
        // temp copy owned by this app — no security-scoped resource access
        // needed, unlike `asCopy: false`.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else {
                onCancel()
                return
            }
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
