import SwiftUI
import UIKit

/// SwiftUI wrapper for `UIActivityViewController` — used instead of
/// `ShareLink` because `ShareLink(item:)` needs its item at render time,
/// which would mean writing the export file to disk on every body
/// evaluation. This wrapper lets a plain Button generate the file once
/// (see `ReceiptListView.exportCSV`) and only then present the share sheet.
///
/// Returning the `UIActivityViewController` directly as this representable's
/// own view controller (i.e. having SwiftUI's `.sheet` host it) caused a
/// real bug, confirmed on-device and reproduced in the Simulator via a
/// screenshot taken immediately after tapping Export: the sheet rendered as
/// a permanently blank white card — never resolving, not even after
/// several seconds. Root cause, found via a first attempted fix that ALSO
/// failed the same way: calling `.present(_:animated:)` for the activity
/// controller from `updateUIViewController` is too early — SwiftUI can (and
/// does) call `updateUIViewController` before the representable's own view
/// has actually been installed in the window hierarchy, so `present` is a
/// silent no-op (no console error, matching what was observed) and nothing
/// ever appears.
///
/// **Fix:** a dedicated `UIViewController` subclass presents the activity
/// controller from `viewDidAppear(_:)` instead — guaranteed to run only
/// once this controller's view is actually on screen — guarded by
/// `hasPresented` so it isn't re-triggered by a later `viewDidAppear` (e.g.
/// after the activity sheet itself is dismissed and this container
/// reappears underneath it).
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> PresentingViewController {
        let controller = PresentingViewController()
        controller.items = items
        return controller
    }

    func updateUIViewController(_ uiViewController: PresentingViewController, context: Context) {
        uiViewController.items = items
    }

    final class PresentingViewController: UIViewController {
        var items: [Any] = []
        private var hasPresented = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasPresented else { return }
            hasPresented = true
            let activityController = UIActivityViewController(activityItems: items, applicationActivities: nil)
            present(activityController, animated: true)
        }
    }
}
