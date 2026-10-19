import SwiftUI
import SwiftData
import UIKit

@main
struct ReceiptTrackerApp: App {
    let container = ReceiptTrackerApp.makeContainer()

    var body: some Scene {
        WindowGroup {
            ReceiptListView()
                .onOpenURL { url in
                    GoogleDriveAuth.handle(url)
                }
                .task {
                    // Silently restores a previous Google sign-in, if any —
                    // must NOT be called from an interactive sign-in button
                    // (see GIDSignIn's own guidance), only once at launch.
                    await GoogleDriveAuth.restorePreviousSignIn()
                }
        }
        .modelContainer(container)
    }

    private static func makeContainer() -> ModelContainer {
        // App Store screenshots only (`AppStoreScreenshotTests`): made-up
        // receipts in a throwaway in-memory store.
        if ProcessInfo.processInfo.environment["UITEST_DEMO_DATA"] != nil {
            if let dir = ProcessInfo.processInfo.environment["UITEST_PDF_IMPORT_DIR"] {
                try? DemoData.writeImportPDFs(to: URL(fileURLWithPath: dir))
            }
            return DemoData.makeContainer()
        }
        let container = try! ModelContainer(for: Receipt.self, CustomCategory.self, CustomGroup.self)

        // Seeds one receipt with a real (tiny, generated) photo attached,
        // gated behind a launch environment variable set only by
        // `ViewReceiptFlowTests`. Avoids driving the system Photos/camera
        // picker in a UI test — documented (Slices 3/4) as unreliable
        // (transient system scrims, picker sheet occasionally sending the
        // whole app to the Home Screen mid-test).
        if let merchant = ProcessInfo.processInfo.environment["UITEST_SEED_PHOTO_MERCHANT"] {
            let context = container.mainContext
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
            let image = renderer.image { ctx in
                UIColor.systemTeal.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            }
            let receipt = Receipt(
                date: Date(),
                totalCost: 9.99,
                merchant: merchant,
                imageData: image.jpegData(compressionQuality: 0.8)
            )
            context.insert(receipt)
            try? context.save()
        }

        // Same idea for a receipt that came from a PDF import (2 pages),
        // set only by `PDFImportFlowTests`.
        if let merchant = ProcessInfo.processInfo.environment["UITEST_SEED_PDF_MERCHANT"] {
            let pageSize = CGSize(width: 300, height: 400)
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize)).pdfData { ctx in
                for page in 1...2 {
                    ctx.beginPage()
                    ("Page \(page)" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
                }
            }
            let photo = UIGraphicsImageRenderer(size: pageSize).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: pageSize))
            }
            let context = container.mainContext
            context.insert(Receipt(date: Date(), totalCost: 7.77, merchant: merchant,
                                   imageData: photo.jpegData(compressionQuality: 0.8), pdfData: pdf))
            try? context.save()
        }

        return container
    }
}
