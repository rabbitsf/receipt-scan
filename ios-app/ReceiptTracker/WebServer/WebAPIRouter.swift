import Foundation
import SwiftData
import UIKit
import PDFKit

/// The `/api/*` contract of the Mac backend (`backend/src/routes/receipts.js`
/// and `settings.js`), re-implemented on the phone so the bundled React web
/// app can run against the phone's own receipts. Each route only translates
/// JSON ↔ models and calls the existing iOS canonical for the behavior:
/// `ReceiptFilter`, `DashboardSummary`, `CustomValueStore`,
/// `ReceiptExtractor`, `ReceiptCSVExporter`, `ReceiptPDFExporter`,
/// `OCRSettings`/`APIKeyStore`.
///
/// Response shapes must stay what `frontend/src/api.js` expects.
@MainActor
final class WebAPIRouter {
    private let context: ModelContext
    private let uploadsDirectory: URL
    private let extract: ([Data]) async throws -> [ExtractedReceipt]
    private let hasAPIKey: (OCRProvider) -> Bool
    private let defaults: UserDefaults

    /// SwiftData has no integer ids, but the web app uses them. Ids are
    /// handed out on first sight and stay stable while the server runs.
    private var idsByModel: [PersistentIdentifier: Int] = [:]
    private var modelsByID: [Int: PersistentIdentifier] = [:]
    private var nextID = 1

    private static let allowedUploadTypes: Set<String> = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]
    private static let receiptImagePrefix = "receipt-"

    init(
        context: ModelContext,
        uploadsDirectory: URL,
        defaults: UserDefaults = .standard,
        hasAPIKey: @escaping (OCRProvider) -> Bool = { APIKeyStore.load(for: $0)?.isEmpty == false },
        extract: @escaping ([Data]) async throws -> [ExtractedReceipt] = { images in
            try await ReceiptExtractor.extractReceipts(images: images, mediaType: "image/jpeg")
        }
    ) {
        self.context = context
        self.uploadsDirectory = uploadsDirectory
        self.defaults = defaults
        self.hasAPIKey = hasAPIKey
        self.extract = extract
    }

    /// Handles any path under `/api`; anything unknown is a JSON 404.
    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let segments = request.pathSegments
        guard segments.first == "api" else { return .error("Not found", status: 404) }
        let rest = Array(segments.dropFirst())

        switch (request.method, rest.first) {
        case ("GET", "health") where rest.count == 1:
            return .json([
                "status": "ok",
                "receiptCount": allReceipts().count,
                "host": "iphone",
                "exportFormats": ["pdf", "csv"],
            ])
        case (_, "settings") where rest.count == 2 && rest[1] == "ocr":
            return handleOCRSettings(request)
        case (_, "receipts"):
            return await handleReceipts(request, path: Array(rest.dropFirst()))
        default:
            return .error("Not found", status: 404)
        }
    }

    // MARK: - Receipts

    private func handleReceipts(_ request: HTTPRequest, path: [String]) async -> HTTPResponse {
        switch (request.method, path.first, path.count) {
        case ("GET", nil, 0): return listReceipts(request)
        case ("POST", nil, 0): return createReceipt(request)
        case ("POST", "upload", 1): return upload(request)
        case ("GET", "images", 2): return image(named: path[1])
        case ("POST", "extract", 1): return await extractFields(request)
        case ("POST", "extract", 2) where path[1] == "estimate": return estimate(request)
        case ("POST", "bulk-delete", 1): return bulkDelete(request)
        case ("GET", "export", 1): return export(request)
        case ("GET", "summary", 1): return summary(request)
        case (_, "categories", _) where path.count <= 2: return customValues(.category, request, name: path.count == 2 ? path[1] : nil)
        case (_, "groups", _) where path.count <= 2: return customValues(.group, request, name: path.count == 2 ? path[1] : nil)
        case (_, let id?, 1):
            guard let receipt = Int(id).flatMap(receipt(withID:)) else { return .error("Receipt not found", status: 404) }
            switch request.method {
            case "GET": return .json(json(for: receipt))
            case "PUT": return updateReceipt(receipt, request)
            case "DELETE":
                delete(receipt)
                return .noContent
            default: return .error("Method not allowed", status: 405)
            }
        default:
            return .error("Not found", status: 404)
        }
    }

    private func listReceipts(_ request: HTTPRequest) -> HTTPResponse {
        switch filteredReceipts(request.query) {
        case .success(let receipts): return .json(receipts.map(json(for:)))
        case .failure(let errors): return .json(["errors": errors.messages], status: 400)
        }
    }

    private func createReceipt(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = request.jsonObject() else { return .error("Invalid JSON body", status: 400) }
        let input = ReceiptInput(body, partial: false)
        guard input.errors.isEmpty, let date = input.date, let totalCost = input.totalCost else {
            return .json(["errors": input.errors], status: 400)
        }
        let receipt = Receipt(
            date: date,
            totalCost: totalCost,
            merchant: input.merchant ?? nil,
            itemDescription: input.description ?? nil,
            category: input.category ?? nil,
            group: input.group ?? nil,
            note: input.note ?? nil,
            imageData: input.imagePath.flatMap { $0.flatMap(imageData(forPath:)) },
            pdfData: input.pdfPath.flatMap { $0.flatMap(pdfData(forPath:)) }
        )
        context.insert(receipt)
        try? context.save()
        return .json(json(for: receipt), status: 201)
    }

    /// Partial update, same merge rules as the backend's `PUT /:id`: a field
    /// left out keeps its value; `imagePath: null` also keeps the photo.
    private func updateReceipt(_ receipt: Receipt, _ request: HTTPRequest) -> HTTPResponse {
        guard let body = request.jsonObject() else { return .error("Invalid JSON body", status: 400) }
        let input = ReceiptInput(body, partial: true)
        guard input.errors.isEmpty else { return .json(["errors": input.errors], status: 400) }

        if let date = input.date { receipt.date = date }
        if let totalCost = input.totalCost { receipt.totalCost = totalCost }
        if let merchant = input.merchant { receipt.merchant = merchant }
        if let description = input.description { receipt.itemDescription = description }
        if let category = input.category { receipt.category = category }
        if let group = input.group { receipt.group = group }
        if let note = input.note { receipt.note = note }
        if case let path?? = input.imagePath, path != imagePath(for: receipt), let data = imageData(forPath: path) {
            receipt.imageData = data
        }
        // `pdfPath`: left out keeps the PDF, null removes it (photo replaced).
        switch input.pdfPath {
        case .none: break
        case .some(.none): receipt.pdfData = nil
        case .some(.some(let path)):
            if path != pdfPath(for: receipt), let data = pdfData(forPath: path) { receipt.pdfData = data }
        }
        receipt.updatedAt = Date()
        try? context.save()
        return .json(json(for: receipt))
    }

    private func bulkDelete(_ request: HTTPRequest) -> HTTPResponse {
        guard let ids = request.jsonObject()?["ids"] as? [Any], !ids.isEmpty,
              let intIDs = Optional(ids.compactMap(Self.integer)), intIDs.count == ids.count else {
            return .error("ids must be a non-empty array of integers", status: 400)
        }
        var deleted: [Int] = []
        var notFound: [Int] = []
        for id in intIDs {
            if let receipt = receipt(withID: id) {
                delete(receipt)
                deleted.append(id)
            } else {
                notFound.append(id)
            }
        }
        return .json(["deleted": deleted, "notFound": notFound])
    }

    private func delete(_ receipt: Receipt) {
        if let id = idsByModel.removeValue(forKey: receipt.persistentModelID) {
            modelsByID[id] = nil
        }
        context.delete(receipt)
        try? context.save()
    }

    private func summary(_ request: HTTPRequest) -> HTTPResponse {
        guard let yearText = request.query["year"], yearText.count == 4, let year = Int(yearText) else {
            return .error("year must be a 4-digit number", status: 400)
        }
        let summary = DashboardSummary.compute(from: allReceipts(), year: year)
        return .json([
            "year": summary.year,
            "yearTotal": Self.dollars(summary.yearTotal),
            "monthlyTotals": summary.monthlyTotals.map { ["month": $0.month, "total": Self.dollars($0.total)] },
            "categoryTotals": summary.categoryTotals.map { ["category": $0.category, "total": Self.dollars($0.total)] },
            "groupTotals": summary.groupTotals.map { ["group": $0.group, "total": Self.dollars($0.total)] },
            "priorYear": summary.priorYear,
            "priorYearTotal": Self.dollars(summary.priorYearTotal),
        ])
    }

    // MARK: - Export

    private func export(_ request: HTTPRequest) -> HTTPResponse {
        let format = request.query["format"] ?? ""
        guard format == "pdf" || format == "csv" else {
            return .error("format must be 'pdf' or 'csv'", status: 400)
        }

        let receipts: [Receipt]
        let filename: String
        if let idList = request.query["ids"] {
            let ids = idList.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !ids.isEmpty else { return .error("ids must be a comma-separated list of integers", status: 400) }
            receipts = sortedNewestFirst(ids.compactMap(receipt(withID:)))
            filename = "receipts-selected.\(format)"
        } else {
            switch filteredReceipts(request.query) {
            case .success(let filtered): receipts = filtered
            case .failure(let errors): return .json(["errors": errors.messages], status: 400)
            }
            filename = Self.exportFilename(request.query, format: format)
        }

        let (contentType, data): (String, Data) = format == "pdf"
            ? ("application/pdf", ReceiptPDFExporter.pdf(for: receipts))
            : ("text/csv; charset=utf-8", Data(ReceiptCSVExporter.csv(for: receipts).utf8))
        return HTTPResponse(status: 200, headers: [
            "Content-Type": contentType,
            "Content-Disposition": "attachment; filename=\"\(filename)\"",
        ], body: data)
    }

    /// Same naming as the backend's `buildExportFilename`.
    static func exportFilename(_ query: [String: String], format: String) -> String {
        var parts = ["receipts"]
        if let year = query["year"], !year.isEmpty { parts.append(year) }
        if let month = query["month"].flatMap({ Int($0) }) { parts.append(String(format: "%02d", month)) }
        if query["category"]?.isEmpty == false { parts.append("category") }
        if query["group"]?.isEmpty == false { parts.append("group") }
        if query["q"]?.isEmpty == false { parts.append("search") }
        return parts.joined(separator: "-") + "." + format
    }

    // MARK: - Photos and scanning

    /// Saves the photo as JPEG (what `Receipt.imageData` always holds) in a
    /// temporary folder; it's copied into a receipt when one is saved with
    /// the returned `imagePath`.
    private func upload(_ request: HTTPRequest) -> HTTPResponse {
        guard let boundary = MultipartFormData.boundary(fromContentType: request.headers["content-type"]),
              let part = MultipartFormData.parse(request.body, boundary: boundary).first(where: { $0.name == "image" }) else {
            return .error("No image file provided (field name: image)", status: 400)
        }
        guard let type = part.contentType?.lowercased(), Self.allowedUploadTypes.contains(type) || type == "application/pdf" else {
            return .error("Only JPEG, PNG, WEBP, HEIC/HEIF images or PDFs are allowed", status: 400)
        }
        if type == "application/pdf" {
            guard PDFDocument(data: part.data) != nil else { return .error("Could not read that PDF", status: 400) }
            let name = UUID().uuidString.lowercased() + ".pdf"
            do {
                try FileManager.default.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true)
                try part.data.write(to: uploadsDirectory.appendingPathComponent(name))
            } catch {
                return .error("Upload failed", status: 500)
            }
            return .json(["pdfPath": "uploads/\(name)"], status: 201)
        }
        guard let jpeg = UIImage(data: part.data)?.jpegData(compressionQuality: 0.8) else {
            return .error("Could not read that image", status: 400)
        }
        let name = UUID().uuidString.lowercased() + ".jpg"
        do {
            try FileManager.default.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true)
            try jpeg.write(to: uploadsDirectory.appendingPathComponent(name))
        } catch {
            return .error("Upload failed", status: 500)
        }
        return .json(["imagePath": "uploads/\(name)"], status: 201)
    }

    private func image(named name: String) -> HTTPResponse {
        if name.hasSuffix(".pdf") {
            guard let data = pdfData(forPath: "uploads/\(name)") else { return .error("PDF not found", status: 404) }
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/pdf", "Cache-Control": "private, max-age=300"], body: data)
        }
        guard let data = imageData(forPath: "uploads/\(name)") else { return .error("Image not found", status: 404) }
        return HTTPResponse(status: 200, headers: ["Content-Type": "image/jpeg", "Cache-Control": "private, max-age=300"], body: data)
    }

    private func extractFields(_ request: HTTPRequest) async -> HTTPResponse {
        let body = request.jsonObject() ?? [:]
        let paths: [Any]
        if let many = body["imagePaths"] as? [Any] {
            paths = many
        } else if let one = body["imagePath"] {
            paths = [one]
        } else {
            paths = []
        }
        let strings = paths.compactMap { $0 as? String }.filter { !$0.isEmpty }
        guard !strings.isEmpty, strings.count == paths.count else {
            return .error("imagePath or a non-empty imagePaths array of strings is required", status: 400)
        }
        // The selected provider's own per-request image limit.
        let maxImages = OCRSettings.selectedProvider(defaults: defaults).maxImagesPerRequest
        guard strings.count <= maxImages else {
            return .error("imagePaths cannot contain more than \(maxImages) images", status: 400)
        }
        var images: [Data] = []
        for path in strings {
            guard let data = imageData(forPath: path) else { return .error("Image not found", status: 404) }
            images.append(data)
        }
        do {
            let receipts = try await extract(images)
            return .json(receipts.map {
                ["date": $0.date, "merchant": $0.merchant, "total_cost": $0.totalCost, "description": $0.description, "pages": $0.pages] as [String: Any]
            })
        } catch {
            return .json(["error": "OCR extraction failed", "detail": error.localizedDescription], status: 502)
        }
    }

    /// Same as the backend's `POST /extract/estimate`: cost and request
    /// limits for scanning images of these sizes with the selected provider.
    private func estimate(_ request: HTTPRequest) -> HTTPResponse {
        guard let sizes = request.jsonObject()?["pageSizes"] as? [[String: Any]] else {
            return .error("pageSizes must be an array of { width, height }", status: 400)
        }
        let pageSizes = sizes.compactMap { size -> (width: Int, height: Int)? in
            guard let w = (size["width"] as? NSNumber)?.intValue, let h = (size["height"] as? NSNumber)?.intValue, w > 0, h > 0 else { return nil }
            return (w, h)
        }
        guard pageSizes.count == sizes.count else { return .error("pageSizes must be an array of { width, height }", status: 400) }
        let provider = OCRSettings.selectedProvider(defaults: defaults)
        let model = OCRSettings.effectiveModel(for: provider, defaults: defaults)
        let estimate = OCRScanCost.estimate(pageSizes: pageSizes, provider: provider, model: model)
        return .json([
            "inputTokens": estimate.inputTokens,
            "outputTokens": estimate.outputTokens,
            "usd": estimate.usd.map { $0 as Any } ?? NSNull(),
            "provider": provider.rawValue,
            "providerName": provider.displayName,
            "model": model,
            "limits": ["maxImagesPerRequest": provider.maxImagesPerRequest, "maxRequestBytes": provider.maxRequestBytes],
        ])
    }

    /// `uploads/receipt-<id>.jpg` is a saved receipt's photo; any other
    /// `uploads/<name>` is a file from `POST /upload`.
    private func imageData(forPath path: String) -> Data? {
        guard path.hasPrefix("uploads/"), !path.hasSuffix(".pdf") else { return nil }
        let name = String(path.dropFirst("uploads/".count))
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        if name.hasPrefix(Self.receiptImagePrefix), name.hasSuffix(".jpg"),
           let id = Int(name.dropFirst(Self.receiptImagePrefix.count).dropLast(4)) {
            return receipt(withID: id)?.imageData
        }
        return try? Data(contentsOf: uploadsDirectory.appendingPathComponent(name))
    }

    /// `uploads/receipt-<id>.pdf` is a saved receipt's PDF; any other
    /// `uploads/<name>.pdf` is a file from `POST /upload`.
    private func pdfData(forPath path: String) -> Data? {
        guard path.hasPrefix("uploads/"), path.hasSuffix(".pdf") else { return nil }
        let name = String(path.dropFirst("uploads/".count))
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        if name.hasPrefix(Self.receiptImagePrefix), let id = Int(name.dropFirst(Self.receiptImagePrefix.count).dropLast(4)) {
            return receipt(withID: id)?.pdfData
        }
        return try? Data(contentsOf: uploadsDirectory.appendingPathComponent(name))
    }

    private func pdfPath(for receipt: Receipt) -> String? {
        receipt.pdfData == nil ? nil : "uploads/\(Self.receiptImagePrefix)\(webID(for: receipt)).pdf"
    }

    private func imagePath(for receipt: Receipt) -> String? {
        receipt.imageData == nil ? nil : "uploads/\(Self.receiptImagePrefix)\(webID(for: receipt)).jpg"
    }

    // MARK: - Categories and groups

    private func customValues(_ kind: CustomValueStore.Kind, _ request: HTTPRequest, name: String?) -> HTTPResponse {
        switch (request.method, name) {
        case ("GET", nil):
            return .json(CustomValueStore.listedNames(kind, in: context))
        case ("POST", nil):
            guard let saved = CustomValueStore.add(request.jsonObject()?["name"] as? String ?? "", kind: kind, in: context) else {
                return .error("name is required", status: 400)
            }
            return .json(["name": saved], status: 201)
        case ("PUT", let oldName?):
            guard let saved = CustomValueStore.rename(oldName, to: request.jsonObject()?["name"] as? String ?? "", kind: kind, in: context) else {
                return .error("name is required and must differ from the current name", status: 400)
            }
            return .json(["name": saved])
        case ("DELETE", let oldName?):
            switch CustomValueStore.delete(oldName, kind: kind, in: context) {
            case .deleted:
                return .noContent
            case .blocked(let count):
                return .json(["error": "Still used by \(count) receipt\(count == 1 ? "" : "s")", "count": count], status: 409)
            }
        default:
            return .error("Not found", status: 404)
        }
    }

    // MARK: - Scanning settings

    /// Same shape as the backend's `getOcrSettings()`. Keys stay on the
    /// phone (Keychain); only whether each one is set is reported.
    private func handleOCRSettings(_ request: HTTPRequest) -> HTTPResponse {
        if request.method == "PUT" {
            let body = request.jsonObject() ?? [:]
            if let dismissed = body["keyWarningDismissed"] {
                guard let flag = dismissed as? Bool, CFGetTypeID(dismissed as CFTypeRef) == CFBooleanGetTypeID() else {
                    return .error("keyWarningDismissed must be a boolean", status: 400)
                }
                OCRSettings.setKeyWarningDismissed(flag, defaults: defaults)
            }
            if let providerID = body["provider"] {
                guard let provider = (providerID as? String).flatMap(OCRProvider.init(rawValue:)) else {
                    return .error("Unknown OCR provider: \(providerID)", status: 400)
                }
                OCRSettings.setSelectedProvider(provider, defaults: defaults)
            }
            // The browser is the phone's owner (they entered the access code), so
            // they may grant or revoke AI permission here too — same rule as Settings.
            if let consent = body["aiConsent"] {
                guard let consent = consent as? [String: Any] else {
                    return .error("aiConsent must be an object of provider → boolean", status: 400)
                }
                for (id, value) in consent {
                    guard let provider = OCRProvider(rawValue: id) else { return .error("Unknown OCR provider: \(id)", status: 400) }
                    guard let allowed = value as? Bool, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else {
                        return .error("aiConsent values must be booleans", status: 400)
                    }
                    AIScanConsent.set(allowed, for: provider, defaults: defaults)
                }
            }
            if let models = body["models"] {
                guard let models = models as? [String: Any] else {
                    return .error("models must be an object of provider → model name", status: 400)
                }
                for (id, model) in models {
                    guard let provider = OCRProvider(rawValue: id) else { return .error("Unknown OCR provider: \(id)", status: 400) }
                    guard let model = model as? String else { return .error("Model must be a string", status: 400) }
                    OCRSettings.setModelOverride(model, for: provider, defaults: defaults)
                }
            }
        } else if request.method != "GET" {
            return .error("Method not allowed", status: 405)
        }

        var providers: [String: Any] = [:]
        for provider in OCRProvider.allCases {
            providers[provider.rawValue] = [
                "displayName": provider.displayName,
                "defaultModel": provider.defaultModel,
                "model": OCRSettings.modelOverride(for: provider, defaults: defaults) ?? "",
                "envVar": "",
                "configured": hasAPIKey(provider),
            ] as [String: Any]
        }
        // Only the phone reports `aiConsent`; the web app asks before scanning
        // when it's present and false (see `frontend/src/scanConsent.js`).
        return .json([
            "provider": OCRSettings.selectedProvider(defaults: defaults).rawValue,
            "providers": providers,
            "keyWarningDismissed": OCRSettings.keyWarningDismissed(defaults: defaults),
            "aiConsent": Dictionary(uniqueKeysWithValues: OCRProvider.allCases.map { ($0.rawValue, AIScanConsent.isGranted(for: $0, defaults: defaults)) }),
            "aiConsentExplanation": Dictionary(uniqueKeysWithValues: OCRProvider.allCases.map { ($0.rawValue, AIScanConsent.explanation(for: $0)) }),
        ])
    }

    // MARK: - Helpers

    private struct FilterErrors: Error { let messages: [String] }

    private func filteredReceipts(_ query: [String: String]) -> Result<[Receipt], FilterErrors> {
        var errors: [String] = []
        let year = query["year"].flatMap { $0.isEmpty ? nil : $0 }
        let month = query["month"].flatMap { $0.isEmpty ? nil : $0 }
        if let year, year.count != 4 || Int(year) == nil { errors.append("year must be a 4-digit number") }
        if let month, !(1...12).contains(Int(month) ?? 0) { errors.append("month must be an integer between 1 and 12") }
        guard errors.isEmpty else { return .failure(FilterErrors(messages: errors)) }

        let filtered = ReceiptFilter.apply(
            to: allReceipts(),
            year: year.flatMap(Int.init),
            month: month.flatMap(Int.init),
            category: query["category"].flatMap { $0.isEmpty ? nil : $0 },
            group: query["group"].flatMap { $0.isEmpty ? nil : $0 },
            searchText: query["q"] ?? ""
        )
        return .success(sortedNewestFirst(filtered))
    }

    private func allReceipts() -> [Receipt] {
        (try? context.fetch(FetchDescriptor<Receipt>())) ?? []
    }

    /// Newest receipt date first, then most recently added — the backend's
    /// `ORDER BY date DESC, id DESC`.
    private func sortedNewestFirst(_ receipts: [Receipt]) -> [Receipt] {
        receipts.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    private func webID(for receipt: Receipt) -> Int {
        let key = receipt.persistentModelID
        if let id = idsByModel[key] { return id }
        let id = nextID
        nextID += 1
        idsByModel[key] = id
        modelsByID[id] = key
        return id
    }

    private func receipt(withID id: Int) -> Receipt? {
        guard let key = modelsByID[id] else { return nil }
        return allReceipts().first { $0.persistentModelID == key }
    }

    private func json(for receipt: Receipt) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        return [
            "id": webID(for: receipt),
            "date": DateOnly.string(from: receipt.date),
            "totalCost": Self.dollars(receipt.totalCost),
            "merchant": receipt.merchant ?? NSNull(),
            "description": receipt.itemDescription ?? NSNull(),
            "category": receipt.category ?? NSNull(),
            "group": receipt.group ?? NSNull(),
            "note": receipt.note ?? NSNull(),
            "imagePath": imagePath(for: receipt) ?? NSNull(),
            "pdfPath": pdfPath(for: receipt) ?? NSNull(),
            "createdAt": iso.string(from: receipt.createdAt),
            "updatedAt": iso.string(from: receipt.updatedAt),
        ]
    }

    private static func dollars(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double == double.rounded() ? Int(double) : nil
    }
}

/// Validated receipt fields from a JSON body (the backend's
/// `validateReceiptInput`). For optional text fields, the outer optional is
/// "was it sent"; the inner one is the value (blank → nil).
private struct ReceiptInput {
    var errors: [String] = []
    var date: Date?
    var totalCost: Double?
    var merchant: String??
    var description: String??
    var category: String??
    var group: String??
    var note: String??
    var imagePath: String??
    var pdfPath: String??

    init(_ body: [String: Any], partial: Bool) {
        if !partial || body["date"] != nil {
            if let text = body["date"] as? String, text.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil, let parsed = DateOnly.date(from: text) {
                date = parsed
            } else {
                errors.append("date must be a valid YYYY-MM-DD string")
            }
        }
        if !partial || body["totalCost"] != nil {
            if let value = Self.number(body["totalCost"]), value.isFinite, value >= 0 {
                totalCost = value
            } else {
                errors.append("totalCost must be a non-negative number")
            }
        }
        merchant = Self.text(body, "merchant")
        description = Self.text(body, "description")
        category = Self.text(body, "category")
        group = Self.text(body, "group")
        note = Self.text(body, "note")
        if let raw = body["imagePath"] {
            imagePath = .some(raw as? String)
        }
        if let raw = body["pdfPath"] {
            if raw is NSNull {
                pdfPath = .some(nil)
            } else if let text = raw as? String, text.wholeMatch(of: /uploads\/[\w-]+\.pdf/) != nil {
                pdfPath = .some(text)
            } else {
                errors.append("pdfPath must be null or an uploaded PDF path")
            }
        }
    }

    private static func text(_ body: [String: Any], _ key: String) -> String?? {
        guard let raw = body[key] else { return nil }
        if raw is NSNull { return .some(nil) }
        let trimmed = "\(raw)".trimmingCharacters(in: .whitespacesAndNewlines)
        return .some(trimmed.isEmpty ? nil : trimmed)
    }

    private static func number(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.doubleValue }
        if let text = raw as? String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? 0 : Double(trimmed)
        }
        return nil
    }
}
