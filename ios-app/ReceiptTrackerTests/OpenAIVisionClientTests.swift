import XCTest
@testable import ReceiptTracker

final class OpenAIVisionClientTests: XCTestCase {
    // MARK: - Request shape

    func testRequestBodyUsesResponsesAPIStructuredOutput() throws {
        let body = OpenAIVisionClient.requestBody(images: [Data("fake-image".utf8)], mediaType: "image/jpeg", model: "gpt-test")

        XCTAssertEqual(body["model"] as? String, "gpt-test")

        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["name"] as? String, "receipts")
        XCTAssertEqual(format["strict"] as? Bool, true)
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["receipts"])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input[0]["role"] as? String, "user")
        let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 3) // "Image 1:" label, image, prompt
        XCTAssertEqual(content[0]["type"] as? String, "input_text")
        XCTAssertEqual(content[0]["text"] as? String, "Image 1:")
        XCTAssertEqual(content[1]["type"] as? String, "input_image")
        XCTAssertEqual(
            content[1]["image_url"] as? String,
            "data:image/jpeg;base64,\(Data("fake-image".utf8).base64EncodedString())"
        )
        XCTAssertEqual(content[2]["type"] as? String, "input_text")
        XCTAssertEqual(content[2]["text"] as? String, ReceiptExtraction.prompt)
    }

    func testRequestBodyWithMultipleImagesIncludesOnePartPerImage() throws {
        let images = [Data("page-1".utf8), Data("page-2".utf8), Data("page-3".utf8)]
        let body = OpenAIVisionClient.requestBody(images: images, mediaType: "image/jpeg", model: "gpt-test")

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 7) // label + image per page, then the prompt
        for (index, imageData) in images.enumerated() {
            XCTAssertEqual(content[2 * index]["text"] as? String, "Image \(index + 1):")
            XCTAssertEqual(content[2 * index + 1]["image_url"] as? String, "data:image/jpeg;base64,\(imageData.base64EncodedString())")
        }
        XCTAssertEqual(content[6]["text"] as? String, ReceiptExtraction.prompt)
    }

    func testMakeRequestUsesBearerAuth() throws {
        let request = try OpenAIVisionClient.makeRequest(images: [Data("x".utf8)], mediaType: "image/jpeg", model: "m", apiKey: "sk-test")
        XCTAssertEqual(request.url, OpenAIVisionClient.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
    }

    // MARK: - Response parsing

    func testParseReceiptsReadsOutputTextFromMessageItem() throws {
        let data = try responsesPayload(text: """
        {"receipts":[{"date":"2026-10-16","merchant":"Test Co","total_cost":12.34,"description":"Widgets"}]}
        """)

        let receipts = try OpenAIVisionClient.parseReceipts(from: data, response: makeHTTPResponse(status: 200))

        XCTAssertEqual(receipts, [ExtractedReceipt(date: "2026-10-16", merchant: "Test Co", totalCost: 12.34, description: "Widgets")])
    }

    /// Reasoning models put a `reasoning` item (no `content`) before the
    /// `message` item — it must be skipped, not treated as an error.
    func testParseReceiptsSkipsNonMessageOutputItems() throws {
        let json: [String: Any] = ["output": [
            ["type": "reasoning", "summary": []],
            ["type": "message", "content": [["type": "output_text", "text": #"{"receipts":[]}"#]]],
        ]]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertEqual(try OpenAIVisionClient.parseReceipts(from: data, response: makeHTTPResponse(status: 200)), [])
    }

    func testParseReceiptsThrowsNoTextContentWhenNoOutputText() throws {
        let json: [String: Any] = ["output": [["type": "message", "content": [["type": "refusal", "refusal": "no"]]]]]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try OpenAIVisionClient.parseReceipts(from: data, response: makeHTTPResponse(status: 200))) { error in
            XCTAssertEqual(error as? OCRError, .noTextContent)
        }
    }

    func testParseReceiptsThrowsServerErrorForNon2xxStatus() throws {
        let data = Data(#"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#.utf8)

        XCTAssertThrowsError(try OpenAIVisionClient.parseReceipts(from: data, response: makeHTTPResponse(status: 401))) { error in
            XCTAssertEqual(error as? OCRError, .server("Incorrect API key provided"))
        }
    }

    func testParseReceiptsThrowsUnexpectedShapeForMalformedJSON() throws {
        let data = try responsesPayload(text: "not valid json")

        XCTAssertThrowsError(try OpenAIVisionClient.parseReceipts(from: data, response: makeHTTPResponse(status: 200))) { error in
            XCTAssertEqual(error as? OCRError, .unexpectedShape)
        }
    }

    // MARK: - Helpers

    private func makeHTTPResponse(status: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: OpenAIVisionClient.endpoint, statusCode: status, httpVersion: nil, headerFields: nil))
    }

    private func responsesPayload(text: String) throws -> Data {
        let json: [String: Any] = ["output": [["type": "message", "content": [["type": "output_text", "text": text]]]]]
        return try JSONSerialization.data(withJSONObject: json)
    }
}
