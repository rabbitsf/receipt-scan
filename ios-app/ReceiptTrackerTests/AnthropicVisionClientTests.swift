import XCTest
@testable import ReceiptTracker

final class AnthropicVisionClientTests: XCTestCase {
    override func tearDown() {
        APIKeyStore.delete()
        super.tearDown()
    }

    // MARK: - Request shape (must match backend/src/services/ocrService.js exactly)

    func testRequestBodyMatchesBackendShape() throws {
        let body = AnthropicVisionClient.requestBody(imageData: Data("fake-image".utf8), mediaType: "image/jpeg")

        XCTAssertEqual(body["model"] as? String, "claude-opus-4-8")
        XCTAssertEqual(body["max_tokens"] as? Int, 4096)

        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")

        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["receipts"])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let receiptsArraySchema = try XCTUnwrap(properties["receipts"] as? [String: Any])
        XCTAssertEqual(receiptsArraySchema["type"] as? String, "array")

        let itemSchema = try XCTUnwrap(receiptsArraySchema["items"] as? [String: Any])
        XCTAssertEqual(
            (itemSchema["required"] as? [String]).map(Set.init),
            Set(["date", "merchant", "total_cost", "description"])
        )
        XCTAssertEqual(itemSchema["additionalProperties"] as? Bool, false)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "image")
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, Data("fake-image".utf8).base64EncodedString())
        XCTAssertEqual(content[1]["type"] as? String, "text")
        XCTAssertFalse((content[1]["text"] as? String ?? "").isEmpty)
    }

    // MARK: - Response parsing

    func testParseReceiptsSucceedsForValidSingleReceiptResponse() throws {
        let response = try makeHTTPResponse(status: 200)
        let data = try messagesAPIPayload(text: """
        {"receipts":[{"date":"2026-07-23","merchant":"Test Co","total_cost":12.34,"description":"Widgets"}]}
        """)

        let receipts = try AnthropicVisionClient.parseReceipts(from: data, response: response)

        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].date, "2026-07-23")
        XCTAssertEqual(receipts[0].merchant, "Test Co")
        XCTAssertEqual(receipts[0].totalCost, 12.34)
        XCTAssertEqual(receipts[0].description, "Widgets")
    }

    func testParseReceiptsSucceedsForMultipleReceipts() throws {
        let response = try makeHTTPResponse(status: 200)
        let data = try messagesAPIPayload(text: """
        {"receipts":[{"date":"2026-07-23","merchant":"A","total_cost":1,"description":"x"},{"date":"2026-07-22","merchant":"B","total_cost":2,"description":"y"}]}
        """)

        let receipts = try AnthropicVisionClient.parseReceipts(from: data, response: response)
        XCTAssertEqual(receipts.count, 2)
    }

    func testParseReceiptsSucceedsForEmptyArray() throws {
        let response = try makeHTTPResponse(status: 200)
        let data = try messagesAPIPayload(text: #"{"receipts":[]}"#)

        let receipts = try AnthropicVisionClient.parseReceipts(from: data, response: response)
        XCTAssertEqual(receipts, [])
    }

    func testParseReceiptsThrowsServerErrorForNon2xxStatus() throws {
        let response = try makeHTTPResponse(status: 401)
        let data = Data(#"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)

        XCTAssertThrowsError(try AnthropicVisionClient.parseReceipts(from: data, response: response)) { error in
            guard case OCRError.server(let message) = error else {
                return XCTFail("Expected OCRError.server, got \(error)")
            }
            XCTAssertEqual(message, "invalid x-api-key")
        }
    }

    func testParseReceiptsThrowsUnexpectedShapeForMalformedJSON() throws {
        let response = try makeHTTPResponse(status: 200)
        let data = try messagesAPIPayload(text: "not valid json")

        XCTAssertThrowsError(try AnthropicVisionClient.parseReceipts(from: data, response: response)) { error in
            XCTAssertEqual(error as? OCRError, .unexpectedShape)
        }
    }

    func testExtractReceiptsThrowsMissingAPIKeyWhenNoneStored() async throws {
        APIKeyStore.delete()
        do {
            _ = try await AnthropicVisionClient.extractReceipts(imageData: Data(), mediaType: "image/jpeg")
            XCTFail("Expected missingAPIKey error")
        } catch OCRError.missingAPIKey {
            // expected
        }
    }

    // MARK: - Helpers

    private func makeHTTPResponse(status: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: AnthropicVisionClient.endpoint, statusCode: status, httpVersion: nil, headerFields: nil))
    }

    private func messagesAPIPayload(text: String) throws -> Data {
        let json: [String: Any] = ["content": [["type": "text", "text": text]]]
        return try JSONSerialization.data(withJSONObject: json)
    }
}
