import XCTest
@testable import ReceiptTracker

final class ReceiptExtractionTests: XCTestCase {
    func testLabelsEachImageInOrderThenPrompt() {
        let blocks = ReceiptExtraction.labeledContent(
            images: [Data([1]), Data([2])],
            text: { "text:\($0)" },
            image: { "image:\($0.first!)" }
        )
        XCTAssertEqual(blocks, ["text:Image 1:", "image:1", "text:Image 2:", "image:2", "text:\(ReceiptExtraction.prompt)"])
    }

    func testSchemaRequiresPages() {
        let fields = ReceiptExtraction.receiptFieldsSchema()
        XCTAssertEqual((fields["required"] as? [String])?.contains("pages"), true)
        let pages = (fields["properties"] as? [String: Any])?["pages"] as? [String: Any]
        XCTAssertEqual(pages?["type"] as? String, "array")
    }

    func testDecodesPagesAndToleratesMissingPages() throws {
        let withPages = try ReceiptExtraction.decodeReceipts(fromJSONText: #"{"receipts":[{"date":"2026-01-02","merchant":"A","total_cost":1.5,"description":"x","pages":[2,3]}]}"#)
        XCTAssertEqual(withPages.first?.pages, [2, 3])
        let without = try ReceiptExtraction.decodeReceipts(fromJSONText: #"{"receipts":[{"date":"2026-01-02","merchant":"A","total_cost":1.5,"description":"x"}]}"#)
        XCTAssertEqual(without.first?.pages, [])
    }

    func testPromptMatchesWebBackend() throws {
        // The web prompt lives in backend/src/services/ocrService.js; both must be identical.
        let source = try String(contentsOfFile: #filePath.replacingOccurrences(of: "ios-app/ReceiptTrackerTests/ReceiptExtractionTests.swift", with: "backend/src/services/ocrService.js"), encoding: .utf8)
        XCTAssertTrue(source.contains(ReceiptExtraction.prompt), "iOS and web scanning prompts differ")
    }
}
