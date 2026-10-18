import XCTest
@testable import ReceiptTracker

final class AnthropicVisionClientTests: XCTestCase {
    // MARK: - Request shape (must match backend/src/services/ocrService.js exactly)

    func testRequestBodyMatchesBackendShape() throws {
        let body = AnthropicVisionClient.requestBody(images: [Data("fake-image".utf8)], mediaType: "image/jpeg", model: "claude-opus-4-8")

        XCTAssertEqual(body["model"] as? String, "claude-opus-4-8")
        XCTAssertEqual(body["max_tokens"] as? Int, ReceiptExtraction.maxOutputTokens)

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
            Set(["date", "merchant", "total_cost", "description", "pages"])
        )
        XCTAssertEqual(itemSchema["additionalProperties"] as? Bool, false)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 3) // "Image 1:" label, image, prompt
        XCTAssertEqual(content[0]["text"] as? String, "Image 1:")
        XCTAssertEqual(content[1]["type"] as? String, "image")
        let source = try XCTUnwrap(content[1]["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, Data("fake-image".utf8).base64EncodedString())
        XCTAssertEqual(content[2]["type"] as? String, "text")
        XCTAssertEqual(content[2]["text"] as? String, ReceiptExtraction.prompt)
    }

    /// Multi-page PDF import sends every rendered page as its own image
    /// block, all in the same request — one image block per page, in
    /// order, followed by exactly one trailing text block.
    func testRequestBodyWithMultipleImagesIncludesOneBlockPerImage() throws {
        let images = [Data("page-1".utf8), Data("page-2".utf8), Data("page-3".utf8)]
        let body = AnthropicVisionClient.requestBody(images: images, mediaType: "image/jpeg", model: "claude-opus-4-8")

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 7) // label + image per page, then the prompt

        for (index, imageData) in images.enumerated() {
            XCTAssertEqual(content[2 * index]["text"] as? String, "Image \(index + 1):")
            XCTAssertEqual(content[2 * index + 1]["type"] as? String, "image")
            let source = try XCTUnwrap(content[2 * index + 1]["source"] as? [String: Any])
            XCTAssertEqual(source["data"] as? String, imageData.base64EncodedString())
        }
        XCTAssertEqual(content[6]["text"] as? String, ReceiptExtraction.prompt)
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

    func testMakeRequestSetsAnthropicHeaders() throws {
        let request = try AnthropicVisionClient.makeRequest(images: [Data("x".utf8)], mediaType: "image/jpeg", model: "m", apiKey: "sk-ant-test")
        XCTAssertEqual(request.url, AnthropicVisionClient.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
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
