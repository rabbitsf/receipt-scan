import SwiftUI
import SwiftData
import UIKit

@main
struct ReceiptTrackerApp: App {
    let container = ReceiptTrackerApp.makeContainer()

    var body: some Scene {
        WindowGroup {
            ReceiptListView()
        }
        .modelContainer(container)
    }

    private static func makeContainer() -> ModelContainer {
        let container = try! ModelContainer(for: Receipt.self)

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

        return container
    }
}
