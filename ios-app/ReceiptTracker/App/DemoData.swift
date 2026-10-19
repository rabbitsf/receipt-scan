import UIKit
import SwiftData

/// Made-up receipts for App Store screenshots (`AppStoreScreenshotTests`),
/// loaded only when the test-only `UITEST_DEMO_DATA` launch variable is set
/// — into an in-memory store, so it never touches real data. All merchants
/// are fictional (no real brands in public screenshots).
enum DemoData {
    struct Item {
        let daysAgo: Int
        let merchant: String
        let total: Double
        let description: String
        let category: String?
        let group: String?
        let note: String?
        let lines: [(String, Double)]
    }

    static let items: [Item] = [
        Item(daysAgo: 0, merchant: "Harbor Coffee Roasters", total: 14.75, description: "Client coffee meeting", category: "Meals & Entertainment", group: nil, note: "With Dana — Q4 plan", lines: [("Flat white", 5.25), ("Cold brew", 4.75), ("Almond croissant", 4.75)]),
        Item(daysAgo: 1, merchant: "Summit Office Supply", total: 86.42, description: "Printer ink, paper, folders", category: "Office Supplies", group: nil, note: nil, lines: [("Ink cartridge XL", 49.99), ("Copy paper (5 reams)", 27.45), ("Folders", 8.98)]),
        Item(daysAgo: 2, merchant: "Northwind Airlines", total: 412.60, description: "SFO → ORD round trip", category: "Travel", group: "Chicago Conference", note: "Economy, 1 checked bag", lines: [("Fare", 362.60), ("Taxes & fees", 50.00)]),
        Item(daysAgo: 3, merchant: "Lakeside Grand Hotel", total: 689.40, description: "3 nights, conference rate", category: "Travel", group: "Chicago Conference", note: nil, lines: [("Room (3 nights)", 597.00), ("Occupancy tax", 92.40)]),
        Item(daysAgo: 4, merchant: "Metro Rideshare", total: 34.18, description: "Airport to hotel", category: "Travel", group: "Chicago Conference", note: nil, lines: [("Ride", 29.68), ("Tip", 4.50)]),
        Item(daysAgo: 6, merchant: "PixelForge Software", total: 59.99, description: "Design suite — monthly", category: "Software/Subscriptions", group: nil, note: "Renews on the 12th", lines: [("Monthly plan", 59.99)]),
        Item(daysAgo: 9, merchant: "City Power & Light", total: 142.87, description: "Office electricity", category: "Utilities", group: nil, note: nil, lines: [("Usage", 128.40), ("Service fee", 14.47)]),
        Item(daysAgo: 12, merchant: "Orchard Electronics", total: 1299.00, description: "Laptop for new hire", category: "Equipment", group: nil, note: "3-year warranty", lines: [("Laptop 14\"", 1199.00), ("Warranty", 100.00)]),
        Item(daysAgo: 15, merchant: "Green Bowl Kitchen", total: 47.30, description: "Team lunch", category: "Meals & Entertainment", group: nil, note: nil, lines: [("Bowls x3", 41.85), ("Drinks", 5.45)]),
        Item(daysAgo: 21, merchant: "Bayline Internet", total: 89.99, description: "Business fiber", category: "Utilities", group: nil, note: nil, lines: [("Fiber 1 Gbps", 89.99)]),
        Item(daysAgo: 33, merchant: "QuickPrint Copy Center", total: 27.50, description: "Brochure printing", category: "Office Supplies", group: nil, note: nil, lines: [("Color prints x50", 27.50)]),
        Item(daysAgo: 41, merchant: "Ridgeview Legal Group", total: 450.00, description: "Contract review", category: "Professional Services", group: nil, note: nil, lines: [("Consultation (2 h)", 450.00)]),
        Item(daysAgo: 58, merchant: "Maple Street Bakery", total: 23.40, description: "Office treats", category: "Meals & Entertainment", group: nil, note: nil, lines: [("Pastry box", 23.40)]),
        Item(daysAgo: 75, merchant: "Summit Office Supply", total: 132.15, description: "Desk organizers, chair mat", category: "Office Supplies", group: nil, note: nil, lines: [("Chair mat", 89.99), ("Organizers", 42.16)]),
        Item(daysAgo: 110, merchant: "Northwind Airlines", total: 288.40, description: "SFO → SEA", category: "Travel", group: "Seattle Client Visit", note: nil, lines: [("Fare", 248.40), ("Taxes & fees", 40.00)]),
        Item(daysAgo: 150, merchant: "PixelForge Software", total: 59.99, description: "Design suite — monthly", category: "Software/Subscriptions", group: nil, note: nil, lines: [("Monthly plan", 59.99)]),
        // Last year, so the Dashboard has something to compare against.
        Item(daysAgo: 320, merchant: "Orchard Electronics", total: 849.00, description: "Monitor and dock", category: "Equipment", group: nil, note: nil, lines: [("27\" monitor", 649.00), ("Dock", 200.00)]),
        Item(daysAgo: 380, merchant: "Northwind Airlines", total: 512.30, description: "SFO → JFK", category: "Travel", group: nil, note: nil, lines: [("Fare", 452.30), ("Taxes & fees", 60.00)]),
        Item(daysAgo: 420, merchant: "City Power & Light", total: 1240.55, description: "Office electricity (Q3)", category: "Utilities", group: nil, note: nil, lines: [("Usage", 1240.55)]),
        Item(daysAgo: 500, merchant: "Ridgeview Legal Group", total: 900.00, description: "Incorporation filing", category: "Professional Services", group: nil, note: nil, lines: [("Filing", 900.00)]),
    ]

    /// An in-memory container filled with `items` (+ one receipt with a 2-page PDF).
    @MainActor
    static func makeContainer() -> ModelContainer {
        let container = try! ModelContainer(
            for: Receipt.self, CustomCategory.self, CustomGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for item in items {
            let date = calendar.date(byAdding: .day, value: -item.daysAgo, to: today)!
            let isHotel = item.merchant == "Lakeside Grand Hotel"
            let image = receiptImage(merchant: item.merchant, date: date, lines: item.lines, total: item.total)
            context.insert(Receipt(
                date: date, totalCost: item.total, merchant: item.merchant, itemDescription: item.description,
                category: item.category, group: item.group, note: item.note,
                imageData: image.jpegData(compressionQuality: 0.85),
                pdfData: isHotel ? hotelFolioPDF(date: date, item: item) : nil
            ))
        }
        context.insert(CustomGroup(name: "Chicago Conference"))
        try? context.save()
        return container
    }

    /// Two-page hotel folio PDFs shown in the PDF import screenshot, written to `folder`.
    static func writeImportPDFs(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let item = items.first { $0.merchant == "Lakeside Grand Hotel" }!
        try hotelFolioPDF(date: Date(), item: item).write(to: folder.appendingPathComponent("Lakeside-Grand-folio.pdf"))
        let page = receiptImage(merchant: "Northwind Airlines", date: Date(), lines: [("Fare", 362.60), ("Taxes & fees", 50.00)], total: 412.60)
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { ctx in
            ctx.beginPage()
            page.draw(in: CGRect(x: 106, y: 40, width: 400, height: 712))
        }
        try pdf.write(to: folder.appendingPathComponent("Northwind-eticket.pdf"))
    }

    // MARK: - Drawing

    static func receiptImage(merchant: String, date: Date, lines: [(String, Double)], total: Double) -> UIImage {
        let size = CGSize(width: 600, height: 1068)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.93, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let paper = CGRect(x: 40, y: 30, width: 520, height: 1008)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: paper, cornerRadius: 6).fill()
            let mono = UIFont.monospacedSystemFont(ofSize: 24, weight: .regular)
            let monoBold = UIFont.monospacedSystemFont(ofSize: 26, weight: .bold)
            let center = NSMutableParagraphStyle()
            center.alignment = .center
            var y: CGFloat = 80
            (merchant.uppercased() as NSString).draw(in: CGRect(x: 60, y: y, width: 480, height: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 34, weight: .heavy), .paragraphStyle: center, .foregroundColor: UIColor.black])
            y += 80
            ("123 Market Street · Springfield" as NSString).draw(in: CGRect(x: 60, y: y, width: 480, height: 30), withAttributes: [.font: mono, .paragraphStyle: center, .foregroundColor: UIColor.darkGray])
            y += 40
            (DateOnly.string(from: date) + "  10:42 AM" as NSString).draw(in: CGRect(x: 60, y: y, width: 480, height: 30), withAttributes: [.font: mono, .paragraphStyle: center, .foregroundColor: UIColor.darkGray])
            y += 70
            func row(_ left: String, _ right: String, font: UIFont) {
                (left as NSString).draw(at: CGPoint(x: 80, y: y), withAttributes: [.font: font, .foregroundColor: UIColor.black])
                let width = (right as NSString).size(withAttributes: [.font: font]).width
                (right as NSString).draw(at: CGPoint(x: 520 - width, y: y), withAttributes: [.font: font, .foregroundColor: UIColor.black])
                y += 44
            }
            for (name, amount) in lines { row(name, String(format: "%.2f", amount), font: mono) }
            y += 10
            ("- - - - - - - - - - - - - - - - - -" as NSString).draw(at: CGPoint(x: 80, y: y), withAttributes: [.font: mono, .foregroundColor: UIColor.gray])
            y += 44
            row("TOTAL", String(format: "$%.2f", total), font: monoBold)
            y += 40
            ("THANK YOU!" as NSString).draw(in: CGRect(x: 60, y: y, width: 480, height: 40), withAttributes: [.font: monoBold, .paragraphStyle: center, .foregroundColor: UIColor.black])
            y += 80
            // barcode
            var x: CGFloat = 130
            var seed = merchant.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 9973 }
            while x < 470 {
                seed = (seed &* 1103 &+ 12345) % 9973
                let w = CGFloat(2 + seed % 4)
                UIColor.black.setFill()
                ctx.fill(CGRect(x: x, y: y, width: w, height: 90))
                x += w + CGFloat(2 + (seed / 7) % 4)
            }
        }
    }

    static func hotelFolioPDF(date: Date, item: Item) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { ctx in
            let title = UIFont.systemFont(ofSize: 26, weight: .bold)
            let body = UIFont.systemFont(ofSize: 14)
            let bold = UIFont.systemFont(ofSize: 14, weight: .semibold)
            for page in 1...2 {
                ctx.beginPage()
                ("LAKESIDE GRAND HOTEL" as NSString).draw(at: CGPoint(x: 56, y: 56), withAttributes: [.font: title])
                ("Guest Folio · Page \(page) of 2" as NSString).draw(at: CGPoint(x: 56, y: 92), withAttributes: [.font: body, .foregroundColor: UIColor.darkGray])
                var y: CGFloat = 140
                let rows: [(String, String)] = page == 1
                    ? [("Arrival", DateOnly.string(from: date)), ("Nights", "3"), ("Room", "King, Lake View"), ("Rate", "$199.00 / night"), ("Room charges", "$597.00")]
                    : [("Occupancy tax", "$92.40"), ("Balance", "$689.40"), ("Payment", "Card ending 4242"), ("Balance due", "$0.00")]
                for (label, value) in rows {
                    (label as NSString).draw(at: CGPoint(x: 56, y: y), withAttributes: [.font: body])
                    (value as NSString).draw(at: CGPoint(x: 360, y: y), withAttributes: [.font: label.contains("Balance") || label.contains("charges") ? bold : body])
                    y += 30
                }
            }
        }
    }
}
