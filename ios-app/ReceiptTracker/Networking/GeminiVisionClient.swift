import Foundation

/// Google Gemini wire format for receipt OCR, via the Interactions API
/// (generateContent is now labelled legacy) with a JSON-schema
/// `response_format`. `store: false` keeps each scan stateless — nothing
/// is kept server-side for later retrieval. Same prompt/schema as every
/// other provider (`ReceiptExtraction`).
enum GeminiVisionClient: VisionOCRClient {
    static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!

    static func makeRequest(images: [Data], mediaType: String, model: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(images: images, mediaType: mediaType, model: model))
        return request
    }

    /// Exposed for unit testing without hitting the network.
    static func requestBody(images: [Data], mediaType: String, model: String) -> [String: Any] {
        let imageParts: [[String: Any]] = images.map { imageData in
            ["type": "image", "data": imageData.base64EncodedString(), "mime_type": mediaType]
        }
        return [
            "model": model,
            "store": false,
            "input": imageParts + [["type": "text", "text": ReceiptExtraction.prompt]],
            "response_format": [
                "type": "text",
                "mime_type": "application/json",
                "schema": ReceiptExtraction.receiptsSchema(),
            ],
        ]
    }

    /// Exposed for unit testing without hitting the network. The model's
    /// text is the `text` content of the `model_output` step in `steps`.
    static func parseReceipts(from data: Data, response: URLResponse) throws -> [ExtractedReceipt] {
        try ReceiptExtraction.validateHTTPResponse(response, data: data)

        let parsed: GeminiInteractionResponse
        do {
            parsed = try JSONDecoder().decode(GeminiInteractionResponse.self, from: data)
        } catch {
            throw OCRError.invalidResponse
        }

        let text = parsed.steps
            .filter { $0.type == "model_output" }
            .flatMap { $0.content ?? [] }
            .first { $0.type == "text" }?
            .text
        guard let text else { throw OCRError.noTextContent }
        return try ReceiptExtraction.decodeReceipts(fromJSONText: text)
    }
}

struct GeminiInteractionResponse: Decodable {
    struct Step: Decodable {
        struct ContentPart: Decodable {
            let type: String
            let text: String?
        }
        let type: String
        let content: [ContentPart]?
    }
    let steps: [Step]
}
