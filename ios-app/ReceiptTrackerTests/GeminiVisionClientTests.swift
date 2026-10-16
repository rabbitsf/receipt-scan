import XCTest
@testable import ReceiptTracker

final class GeminiVisionClientTests: XCTestCase {
    // MARK: - Request shape

    func testRequestBodyUsesInteractionsAPIJSONSchemaFormat() throws {
        let body = GeminiVisionClient.requestBody(images: [Data("fake-image".utf8)], mediaType: "image/jpeg", model: "gemini-test")

        XCTAssertEqual(body["model"] as? String, "gemini-test")
        XCTAssertEqual(body["store"] as? Bool, false)

        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "text")
        XCTAssertEqual(format["mime_type"] as? String, "application/json")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["receipts"])

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["type"] as? String, "image")
        XCTAssertEqual(input[0]["data"] as? String, Data("fake-image".utf8).base64EncodedString())
        XCTAssertEqual(input[0]["mime_type"] as? String, "image/jpeg")
        XCTAssertEqual(input[1]["type"] as? String, "text")
        XCTAssertEqual(input[1]["text"] as? String, ReceiptExtraction.prompt)
    }

    func testRequestBodyWithMultipleImagesIncludesOnePartPerImage() throws {
        let images = [Data("page-1".utf8), Data("page-2".utf8), Data("page-3".utf8)]
        let body = GeminiVisionClient.requestBody(images: images, mediaType: "image/jpeg", model: "gemini-test")

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 4)
        for (index, imageData) in images.enumerated() {
            XCTAssertEqual(input[index]["data"] as? String, imageData.base64EncodedString())
        }
        XCTAssertEqual(input[3]["type"] as? String, "text")
    }

    func testMakeRequestUsesGoogleAPIKeyHeader() throws {
        let request = try GeminiVisionClient.makeRequest(images: [Data("x".utf8)], mediaType: "image/jpeg", model: "m", apiKey: "AIza-test")
        XCTAssertEqual(request.url, GeminiVisionClient.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "AIza-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - Response parsing

    func testParseReceiptsReadsTextFromModelOutputStep() throws {
        let json: [String: Any] = ["steps": [
            ["type": "user_input", "content": [["type": "text", "text": "ignored"]]],
            ["type": "model_output", "content": [[
                "type": "text",
                "text": #"{"receipts":[{"date":"2026-10-16","merchant":"Test Co","total_cost":5,"description":"Coffee"}]}"#,
            ]]],
        ]]
        let data = try JSONSerialization.data(withJSONObject: json)

        let receipts = try GeminiVisionClient.parseReceipts(from: data, response: makeHTTPResponse(status: 200))

        XCTAssertEqual(receipts, [ExtractedReceipt(date: "2026-10-16", merchant: "Test Co", totalCost: 5, description: "Coffee")])
    }

    func testParseReceiptsThrowsNoTextContentWithoutModelOutput() throws {
        let data = try JSONSerialization.data(withJSONObject: ["steps": [["type": "user_input"]]])

        XCTAssertThrowsError(try GeminiVisionClient.parseReceipts(from: data, response: makeHTTPResponse(status: 200))) { error in
            XCTAssertEqual(error as? OCRError, .noTextContent)
        }
    }

    func testParseReceiptsThrowsServerErrorForNon2xxStatus() throws {
        let data = Data(#"{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT"}}"#.utf8)

        XCTAssertThrowsError(try GeminiVisionClient.parseReceipts(from: data, response: makeHTTPResponse(status: 400))) { error in
            XCTAssertEqual(error as? OCRError, .server("API key not valid."))
        }
    }

    // MARK: - Helpers

    private func makeHTTPResponse(status: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: GeminiVisionClient.endpoint, statusCode: status, httpVersion: nil, headerFields: nil))
    }
}
