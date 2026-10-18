import PDFKit
import UIKit

/// One receipt waiting in the Add Receipt review queue ("Receipt X of N"),
/// with its own photo and — when it came from a PDF — its own pages.
struct ScanReviewItem: Equatable {
    /// nil when nothing was detected or scanning failed: the user fills it in.
    var fields: ExtractedReceipt?
    var imageData: Data?
    var pdfData: Data?
    /// e.g. "From invoice.pdf · pages 1–2".
    var sourceLabel: String?
    /// Warnings to show with this entry.
    var notices: [String] = []
}

/// THE PDF import pipeline (iOS): several files, each scanned on its own,
/// shrunk/split per `PDFScanBudget`, pages matched to receipts per
/// `PDFPageAssignment`, each receipt given its own PDF (`PDFSubset`) and
/// first-page photo. Mirrors `frontend/src/pdfImport.js`.
enum PDFImportScanner {
    struct File: Sendable {
        let name: String
        let data: Data
    }

    enum Scope: Equatable, Sendable {
        case allPages
        case firstPages(Int)

        func pageCount(of total: Int) -> Int {
            switch self {
            case .allPages: return total
            case .firstPages(let n): return min(n, total)
            }
        }
    }

    struct CostSummary: Equatable {
        /// (file name, page count) for the popup text.
        let files: [(name: String, pages: Int)]
        let totalPages: Int
        let allPagesUSD: Double?
        /// Pages and cost if only the first `PDFPageRenderer.quickScanPages` of each file are scanned.
        let quickScanPages: Int
        let quickScanUSD: Double?

        static func == (lhs: CostSummary, rhs: CostSummary) -> Bool {
            lhs.files.map(\.name) == rhs.files.map(\.name) && lhs.files.map(\.pages) == rhs.files.map(\.pages)
                && lhs.totalPages == rhs.totalPages && lhs.allPagesUSD == rhs.allPagesUSD
                && lhs.quickScanPages == rhs.quickScanPages && lhs.quickScanUSD == rhs.quickScanUSD
        }
    }

    /// Page counts and estimated cost for the cost popup — no rendering.
    /// Each file is its own scan, so the total is the sum of per-file
    /// estimates. Unreadable files count as 0 pages.
    static func costSummary(files: [File], provider: OCRProvider, model: String) -> CostSummary {
        var named: [(name: String, pages: Int)] = []
        var allPages = 0, quickPages = 0
        var allUSD: Double? = 0, quickUSD: Double? = 0
        func add(_ total: inout Double?, _ estimate: OCRScanCost.Estimate) {
            if let usd = estimate.usd, let sum = total { total = sum + usd } else { total = nil }
        }
        for file in files {
            guard let document = PDFDocument(data: file.data) else {
                named.append((file.name, 0))
                continue
            }
            let total = document.pageCount
            let quick = min(total, PDFPageRenderer.quickScanPages)
            named.append((file.name, total))
            allPages += total
            quickPages += quick
            let allSizes = PDFPageRenderer.renderedSizes(of: document, pages: 0..<total, maxEdge: PDFScanBudget.steps(pageCount: total)[0].maxEdge)
            let quickSizes = PDFPageRenderer.renderedSizes(of: document, pages: 0..<quick, maxEdge: PDFScanBudget.steps(pageCount: quick)[0].maxEdge)
            add(&allUSD, OCRScanCost.estimate(pageSizes: allSizes, provider: provider, model: model))
            add(&quickUSD, OCRScanCost.estimate(pageSizes: quickSizes, provider: provider, model: model))
        }
        return CostSummary(files: named, totalPages: allPages, allPagesUSD: allUSD,
                           quickScanPages: quickPages, quickScanUSD: quickUSD)
    }

    /// Scans every file in order, reporting `progress(fileNumber, fileCount)`.
    /// Never throws: a file that can't be read or scanned becomes one blank
    /// entry with its whole PDF attached and a notice.
    static func scan(
        files: [File],
        scope: Scope,
        provider: OCRProvider,
        extract: @Sendable ([Data]) async throws -> [ExtractedReceipt],
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> [ScanReviewItem] {
        var items: [ScanReviewItem] = []
        for (index, file) in files.enumerated() {
            await progress(index + 1, files.count)
            items += await scanFile(file, scope: scope, provider: provider, extract: extract)
        }
        return items
    }

    static func scanFile(
        _ file: File,
        scope: Scope,
        provider: OCRProvider,
        extract: @Sendable ([Data]) async throws -> [ExtractedReceipt]
    ) async -> [ScanReviewItem] {
        guard let document = PDFDocument(data: file.data), document.pageCount > 0 else {
            return [ScanReviewItem(fields: nil, imageData: nil, pdfData: file.data, sourceLabel: "From \(file.name)",
                                   notices: ["Couldn't read \(file.name) — please enter this receipt by hand."])]
        }
        let total = document.pageCount
        let scanned = scope.pageCount(of: total)
        let prepared = PDFScanBudget.prepare(document: document, pageCount: scanned, provider: provider)

        var fileNotices: [String] = []
        if prepared.parts.count > 1 {
            fileNotices.append("\(file.name) was too large to scan at once, so it was scanned in \(prepared.parts.count) parts — a receipt that crosses parts may appear twice.")
        }

        var receipts: [ExtractedReceipt] = []
        do {
            for part in prepared.parts {
                let found = try await extract(Array(prepared.images[part]))
                receipts += found.map { receipt in
                    ExtractedReceipt(date: receipt.date, merchant: receipt.merchant, totalCost: receipt.totalCost,
                                     description: receipt.description,
                                     pages: PDFPageAssignment.filePages(receipt.pages, part: part))
                }
            }
        } catch {
            return [blankItem(for: file, document: document, notices: fileNotices + ["Scanning \(file.name) failed (\(error.localizedDescription)) — please check the fields."])]
        }
        guard !receipts.isEmpty else {
            return [blankItem(for: file, document: document, notices: fileNotices + ["No receipt details were found in \(file.name) — please enter them by hand."])]
        }

        let assignment = PDFPageAssignment.assign(receiptPages: receipts.map(\.pages), scannedPageCount: scanned, totalPageCount: total)
        if let first = assignment.unkeptPages.first, let last = assignment.unkeptPages.last {
            let range = first == last ? "Page \(first)" : "Pages \(first)–\(last)"
            fileNotices.append("\(range) of \(file.name) weren't scanned and aren't kept with these receipts.")
        }
        return zip(receipts, assignment.pagesPerReceipt).map { receipt, pages in
            ScanReviewItem(
                fields: receipt,
                imageData: photo(of: document, page: pages.first ?? 1),
                pdfData: PDFSubset.data(of: document, originalData: file.data, pages: pages) ?? file.data,
                sourceLabel: "From \(file.name) · \(PDFPageAssignment.label(pages))",
                notices: fileNotices
            )
        }
    }

    private static func blankItem(for file: File, document: PDFDocument, notices: [String]) -> ScanReviewItem {
        ScanReviewItem(fields: nil, imageData: photo(of: document, page: 1), pdfData: file.data,
                       sourceLabel: "From \(file.name)", notices: notices)
    }

    /// The receipt's photo: its first page at normal photo quality.
    private static func photo(of document: PDFDocument, page: Int) -> Data? {
        PDFPageRenderer.renderJPEGs(of: document, pages: (page - 1)..<page, maxEdge: 2200, quality: 0.8).first
    }
}
