import XCTest
import SwiftData
import UIKit
import PDFKit
@testable import ReceiptTracker

@MainActor
final class WebAPIRouterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var router: WebAPIRouter!
    private var defaults: UserDefaults!
    private var uploads: URL!
    private var extractedImageCounts: [Int] = []

    override func setUp() async throws {
        container = try ModelContainer(
            for: Receipt.self, CustomCategory.self, CustomGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        defaults = UserDefaults(suiteName: "WebAPIRouterTests")!
        defaults.removePersistentDomain(forName: "WebAPIRouterTests")
        uploads = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        extractedImageCounts = []
        router = WebAPIRouter(
            context: context,
            uploadsDirectory: uploads,
            defaults: defaults,
            hasAPIKey: { $0 == .openai },
            extract: { [unowned self] images in
                self.extractedImageCounts.append(images.count)
                return [ExtractedReceipt(date: "2026-03-04", merchant: "Cafe", totalCost: 4.5, description: "Coffee")]
            }
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: uploads)
    }

    // MARK: - Helpers

    private func call(_ method: String, _ target: String, json: Any? = nil, rawBody: Data? = nil, contentType: String? = nil) async -> (status: Int, body: Any?, response: HTTPResponse) {
        let body = rawBody ?? json.map { try! JSONSerialization.data(withJSONObject: $0) } ?? Data()
        var head = "\(method) \(target) HTTP/1.1\r\nContent-Length: \(body.count)\r\n"
        if let contentType { head += "Content-Type: \(contentType)\r\n" }
        guard case .complete(let request) = HTTPRequestParser.parse(Data((head + "\r\n").utf8) + body) else {
            fatalError("bad test request")
        }
        let response = await router.handle(request)
        let parsed = try? JSONSerialization.jsonObject(with: response.body, options: [.fragmentsAllowed])
        return (response.status, parsed, response)
    }

    @discardableResult
    private func create(_ fields: [String: Any]) async -> [String: Any] {
        let result = await call("POST", "/api/receipts", json: fields)
        XCTAssertEqual(result.status, 201, "\(String(describing: result.body))")
        return result.body as! [String: Any]
    }

    private func pngData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func upload() async -> String {
        let boundary = "XYZ"
        let body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"r.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)
            + pngData() + Data("\r\n--\(boundary)--\r\n".utf8)
        let result = await call("POST", "/api/receipts/upload", rawBody: body, contentType: "multipart/form-data; boundary=\(boundary)")
        XCTAssertEqual(result.status, 201)
        return (result.body as! [String: Any])["imagePath"] as! String
    }

    // MARK: - Receipts

    func testHealthReportsPhoneHostAndExportFormats() async {
        let body = await call("GET", "/api/health").body as! [String: Any]
        XCTAssertEqual(body["host"] as? String, "iphone")
        XCTAssertEqual(body["exportFormats"] as? [String], ["pdf", "csv"])
    }

    func testCreateReturnsWebShapeAndSavesToSwiftData() async throws {
        let created = await create(["date": "2026-05-06", "totalCost": "12.345", "merchant": " Shop ", "description": "", "category": "Travel", "note": NSNull()])
        XCTAssertEqual(created["date"] as? String, "2026-05-06")
        XCTAssertEqual(created["totalCost"] as? Double, 12.35)
        XCTAssertEqual(created["merchant"] as? String, "Shop")
        XCTAssertTrue(created["description"] is NSNull)
        XCTAssertTrue(created["imagePath"] is NSNull)
        XCTAssertNotNil(created["id"] as? Int)

        let saved = try context.fetch(FetchDescriptor<Receipt>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(DateOnly.string(from: saved[0].date), "2026-05-06")
        XCTAssertEqual(saved[0].category, "Travel")
    }

    func testCreateValidatesLikeBackend() async {
        let result = await call("POST", "/api/receipts", json: ["date": "May 6", "totalCost": -1])
        XCTAssertEqual(result.status, 400)
        XCTAssertEqual((result.body as? [String: Any])?["errors"] as? [String], [
            "date must be a valid YYYY-MM-DD string", "totalCost must be a non-negative number",
        ])
    }

    func testListFiltersAndSortsNewestFirst() async {
        await create(["date": "2026-01-10", "totalCost": 1, "merchant": "Alpha", "category": "Travel"])
        await create(["date": "2026-03-10", "totalCost": 2, "merchant": "Beta", "category": "Travel"])
        await create(["date": "2025-03-10", "totalCost": 3, "merchant": "Gamma"])

        let all = await call("GET", "/api/receipts").body as! [[String: Any]]
        XCTAssertEqual(all.compactMap { $0["merchant"] as? String }, ["Beta", "Alpha", "Gamma"])

        let filtered = await call("GET", "/api/receipts?year=2026&category=Travel&q=alp").body as! [[String: Any]]
        XCTAssertEqual(filtered.compactMap { $0["merchant"] as? String }, ["Alpha"])

        let bad = await call("GET", "/api/receipts?month=13")
        XCTAssertEqual(bad.status, 400)
    }

    func testUpdateIsPartialAndDeleteRemoves() async {
        let created = await create(["date": "2026-01-10", "totalCost": 1, "merchant": "Alpha", "note": "keep"])
        let id = created["id"] as! Int

        let updated = await call("PUT", "/api/receipts/\(id)", json: ["merchant": "Renamed", "totalCost": 9.5])
        XCTAssertEqual(updated.status, 200)
        let body = updated.body as! [String: Any]
        XCTAssertEqual(body["merchant"] as? String, "Renamed")
        XCTAssertEqual(body["note"] as? String, "keep")
        XCTAssertEqual(body["totalCost"] as? Double, 9.5)

        let fetched = await call("GET", "/api/receipts/\(id)").body as! [String: Any]
        XCTAssertEqual(fetched["merchant"] as? String, "Renamed")

        let deleted = await call("DELETE", "/api/receipts/\(id)")
        XCTAssertEqual(deleted.status, 204)
        let missing = await call("GET", "/api/receipts/\(id)")
        XCTAssertEqual(missing.status, 404)
    }

    func testBulkDeleteReportsDeletedAndNotFound() async {
        let a = await create(["date": "2026-01-10", "totalCost": 1])["id"] as! Int
        let b = await create(["date": "2026-01-11", "totalCost": 2])["id"] as! Int
        let result = await call("POST", "/api/receipts/bulk-delete", json: ["ids": [a, b, 999]])
        let body = result.body as! [String: Any]
        XCTAssertEqual(body["deleted"] as? [Int], [a, b])
        XCTAssertEqual(body["notFound"] as? [Int], [999])
        let invalid = await call("POST", "/api/receipts/bulk-delete", json: ["ids": ["x"]])
        XCTAssertEqual(invalid.status, 400)
    }

    func testSummaryUsesDashboardSummaryShape() async {
        await create(["date": "2026-02-01", "totalCost": 10, "category": "Travel", "group": "Trip"])
        await create(["date": "2025-02-01", "totalCost": 4])
        let body = await call("GET", "/api/receipts/summary?year=2026").body as! [String: Any]
        XCTAssertEqual(body["yearTotal"] as? Double, 10)
        XCTAssertEqual(body["priorYearTotal"] as? Double, 4)
        XCTAssertEqual((body["monthlyTotals"] as? [[String: Any]])?.count, 12)
        XCTAssertEqual((body["categoryTotals"] as? [[String: Any]])?.first?["category"] as? String, "Travel")
        XCTAssertEqual((body["groupTotals"] as? [[String: Any]])?.first?["group"] as? String, "Trip")
    }

    // MARK: - Photos and scanning

    func testUploadExtractAndSaveCopiesPhotoIntoReceipt() async throws {
        let path = await upload()
        XCTAssertTrue(path.hasPrefix("uploads/") && path.hasSuffix(".jpg"))

        let image = await call("GET", "/api/receipts/images/\(path.dropFirst("uploads/".count))")
        XCTAssertEqual(image.status, 200)
        XCTAssertEqual(image.response.headers["Content-Type"], "image/jpeg")

        let extracted = await call("POST", "/api/receipts/extract", json: ["imagePaths": [path, path]])
        XCTAssertEqual(extractedImageCounts, [2])
        XCTAssertEqual((extracted.body as? [[String: Any]])?.first?["total_cost"] as? Double, 4.5)

        let created = await create(["date": "2026-03-04", "totalCost": 4.5, "imagePath": path])
        let savedPath = try XCTUnwrap(created["imagePath"] as? String)
        XCTAssertTrue(savedPath.hasPrefix("uploads/receipt-"))
        let receipt = try XCTUnwrap(context.fetch(FetchDescriptor<Receipt>()).first)
        XCTAssertNotNil(receipt.imageData)

        // Saved photo is served under its receipt path, and re-sending it on update keeps it.
        let savedImage = await call("GET", "/api/receipts/images/\(savedPath.dropFirst("uploads/".count))")
        XCTAssertEqual(savedImage.response.body, receipt.imageData)
        let updated = await call("PUT", "/api/receipts/\(created["id"] as! Int)", json: ["imagePath": savedPath])
        XCTAssertEqual((updated.body as? [String: Any])?["imagePath"] as? String, savedPath)
    }

    func testUploadRejectsNonImageTypesAndPathTricks() async {
        let body = Data("--B\r\nContent-Disposition: form-data; name=\"image\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhi\r\n--B--\r\n".utf8)
        let result = await call("POST", "/api/receipts/upload", rawBody: body, contentType: "multipart/form-data; boundary=B")
        XCTAssertEqual(result.status, 400)
        let traversal = await call("POST", "/api/receipts/extract", json: ["imagePath": "uploads/../../etc/passwd"])
        XCTAssertEqual(traversal.status, 404)
        let tooMany = await call("POST", "/api/receipts/extract", json: ["imagePaths": Array(repeating: "uploads/a.jpg", count: OCRProvider.anthropic.maxImagesPerRequest + 1)])
        XCTAssertEqual(tooMany.status, 400)
    }

    // MARK: - Export

    func testExportCSVAndPDF() async {
        let id = await create(["date": "2026-01-10", "totalCost": 1, "merchant": "Alpha"])["id"] as! Int
        await create(["date": "2026-01-11", "totalCost": 2, "merchant": "Beta"])

        let csv = await call("GET", "/api/receipts/export?format=csv&ids=\(id)")
        XCTAssertEqual(csv.response.headers["Content-Disposition"], "attachment; filename=\"receipts-selected.csv\"")
        let text = String(decoding: csv.response.body, as: UTF8.self)
        XCTAssertTrue(text.contains("Alpha"))
        XCTAssertFalse(text.contains("Beta"))

        let pdf = await call("GET", "/api/receipts/export?format=pdf&year=2026&month=1")
        XCTAssertEqual(pdf.response.headers["Content-Type"], "application/pdf")
        XCTAssertEqual(pdf.response.headers["Content-Disposition"], "attachment; filename=\"receipts-2026-01.pdf\"")
        XCTAssertTrue(pdf.response.body.starts(with: Data("%PDF".utf8)))

        let xlsx = await call("GET", "/api/receipts/export?format=xlsx")
        XCTAssertEqual(xlsx.status, 400)
    }

    // MARK: - Categories, groups, settings

    func testCategoryAndGroupRoutesUseCustomValueStore() async {
        let added = await call("POST", "/api/receipts/categories", json: ["name": "Snacks & Co"])
        XCTAssertEqual(added.status, 201)
        let renamed = await call("PUT", "/api/receipts/categories/Snacks%20%26%20Co", json: ["name": "Food"])
        XCTAssertEqual((renamed.body as? [String: Any])?["name"] as? String, "Food")
        let listed = await call("GET", "/api/receipts/categories").body as? [String]
        XCTAssertEqual(listed, ["Food"])

        await create(["date": "2026-01-10", "totalCost": 1, "group": "Trip"])
        let blocked = await call("DELETE", "/api/receipts/groups/Trip")
        XCTAssertEqual(blocked.status, 409)
        XCTAssertEqual((blocked.body as? [String: Any])?["count"] as? Int, 1)
        let deleted = await call("DELETE", "/api/receipts/categories/Food")
        XCTAssertEqual(deleted.status, 204)
    }

    func testOCRSettingsReadAndWrite() async {
        var body = await call("GET", "/api/settings/ocr").body as! [String: Any]
        XCTAssertEqual(body["provider"] as? String, "anthropic")
        XCTAssertEqual(((body["providers"] as? [String: Any])?["openai"] as? [String: Any])?["configured"] as? Bool, true)
        XCTAssertEqual(((body["providers"] as? [String: Any])?["anthropic"] as? [String: Any])?["configured"] as? Bool, false)

        body = await call("PUT", "/api/settings/ocr", json: ["provider": "gemini", "models": ["gemini": "g-custom"], "keyWarningDismissed": true]).body as! [String: Any]
        XCTAssertEqual(body["provider"] as? String, "gemini")
        XCTAssertEqual(body["keyWarningDismissed"] as? Bool, true)
        XCTAssertEqual(OCRSettings.effectiveModel(for: .gemini, defaults: defaults), "g-custom")

        let bad = await call("PUT", "/api/settings/ocr", json: ["keyWarningDismissed": "yes"])
        XCTAssertEqual(bad.status, 400)
        let unknown = await call("PUT", "/api/settings/ocr", json: ["provider": "nope"])
        XCTAssertEqual(unknown.status, 400)
    }

    func testExportFilenameMatchesBackend() {
        XCTAssertEqual(WebAPIRouter.exportFilename(["year": "2026", "month": "3", "q": "x"], format: "csv"), "receipts-2026-03-search.csv")
        XCTAssertEqual(WebAPIRouter.exportFilename([:], format: "pdf"), "receipts.pdf")
    }

    // MARK: - PDF receipts

    private func uploadPDF(pages: Int) async -> String {
        let body = Data("--P\r\nContent-Disposition: form-data; name=\"image\"; filename=\"r.pdf\"\r\nContent-Type: application/pdf\r\n\r\n".utf8)
            + TestPDF.make(pageCount: pages) + Data("\r\n--P--\r\n".utf8)
        let result = await call("POST", "/api/receipts/upload", rawBody: body, contentType: "multipart/form-data; boundary=P")
        XCTAssertEqual(result.status, 201)
        return (result.body as! [String: Any])["pdfPath"] as! String
    }

    func testPDFUploadSaveServeKeepAndClear() async throws {
        let uploaded = await uploadPDF(pages: 2)
        XCTAssertTrue(uploaded.hasSuffix(".pdf"))

        let created = await create(["date": "2026-03-04", "totalCost": 4.5, "pdfPath": uploaded])
        let savedPath = try XCTUnwrap(created["pdfPath"] as? String)
        XCTAssertTrue(savedPath.hasPrefix("uploads/receipt-") && savedPath.hasSuffix(".pdf"))
        let receipt = try XCTUnwrap(context.fetch(FetchDescriptor<Receipt>()).first)
        XCTAssertEqual(receipt.pdfData.flatMap { PDFDocument(data: $0)?.pageCount }, 2)

        let served = await call("GET", "/api/receipts/images/\(savedPath.dropFirst("uploads/".count))")
        XCTAssertEqual(served.response.headers["Content-Type"], "application/pdf")
        XCTAssertEqual(served.response.body, receipt.pdfData)

        let id = created["id"] as! Int
        let kept = await call("PUT", "/api/receipts/\(id)", json: ["merchant": "X"])
        XCTAssertEqual((kept.body as? [String: Any])?["pdfPath"] as? String, savedPath)
        let cleared = await call("PUT", "/api/receipts/\(id)", json: ["pdfPath": NSNull()])
        XCTAssertTrue((cleared.body as? [String: Any])?["pdfPath"] is NSNull)
        XCTAssertNil(receipt.pdfData)

        let bad = await call("PUT", "/api/receipts/\(id)", json: ["pdfPath": "../secret.pdf"])
        XCTAssertEqual(bad.status, 400)
        let pdfAsImage = await call("POST", "/api/receipts/extract", json: ["imagePath": uploaded])
        XCTAssertEqual(pdfAsImage.status, 404, "a PDF path is never sent to the AI as an image")
    }

    func testExtractReturnsPagesAndEstimateUsesSelectedProvider() async {
        let path = await upload()
        let extracted = await call("POST", "/api/receipts/extract", json: ["imagePath": path])
        XCTAssertEqual((extracted.body as? [[String: Any]])?.first?["pages"] as? [Int], [])

        let estimate = await call("POST", "/api/receipts/extract/estimate", json: ["pageSizes": [["width": 1700, "height": 2200]]])
        let body = estimate.body as! [String: Any]
        XCTAssertEqual(body["provider"] as? String, "anthropic")
        XCTAssertEqual((body["limits"] as? [String: Any])?["maxRequestBytes"] as? Int, 32 * 1024 * 1024)
        XCTAssertGreaterThan(body["usd"] as? Double ?? 0, 0)
        let bad = await call("POST", "/api/receipts/extract/estimate", json: ["pageSizes": [["width": 0]]])
        XCTAssertEqual(bad.status, 400)
    }
}
