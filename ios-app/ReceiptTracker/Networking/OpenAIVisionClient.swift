import Foundation

/// OpenAI wire format for receipt OCR, via the Responses API with strict
/// Structured Outputs. Same prompt/schema as every other provider
/// (`ReceiptExtraction`); see `AnthropicVisionClient` for why multiple
/// images go in one request.
enum OpenAIVisionClient: VisionOCRClient {
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    static func makeRequest(images: [Data], mediaType: String, model: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(images: images, mediaType: mediaType, model: model))
        return request
    }

    /// Exposed for unit testing without hitting the network.
    static func requestBody(images: [Data], mediaType: String, model: String) -> [String: Any] {
        let imageParts: [[String: Any]] = images.map { imageData in
            [
                "type": "input_image",
                "image_url": "data:\(mediaType);base64,\(imageData.base64EncodedString())",
            ]
        }
        return [
            "model": model,
            "input": [[
                "role": "user",
                "content": imageParts + [["type": "input_text", "text": ReceiptExtraction.prompt]],
            ]],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "receipts",
                    "schema": ReceiptExtraction.receiptsSchema(),
                    "strict": true,
                ],
            ],
        ]
    }

    /// Exposed for unit testing without hitting the network. The model's
    /// text is the `output_text` part of the `message` item in `output`.
    static func parseReceipts(from data: Data, response: URLResponse) throws -> [ExtractedReceipt] {
        try ReceiptExtraction.validateHTTPResponse(response, data: data)

        let parsed: OpenAIResponsesAPIResponse
        do {
            parsed = try JSONDecoder().decode(OpenAIResponsesAPIResponse.self, from: data)
        } catch {
            throw OCRError.invalidResponse
        }

        let text = parsed.output
            .filter { $0.type == "message" }
            .flatMap { $0.content ?? [] }
            .first { $0.type == "output_text" }?
            .text
        guard let text else { throw OCRError.noTextContent }
        return try ReceiptExtraction.decodeReceipts(fromJSONText: text)
    }
}

struct OpenAIResponsesAPIResponse: Decodable {
    struct OutputItem: Decodable {
        struct ContentPart: Decodable {
            let type: String
            let text: String?
        }
        let type: String
        let content: [ContentPart]?
    }
    let output: [OutputItem]
}
