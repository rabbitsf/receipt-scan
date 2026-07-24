import Foundation

struct ExtractedReceipt: Decodable, Equatable {
    let date: String
    let merchant: String
    let totalCost: Double
    let description: String

    enum CodingKeys: String, CodingKey {
        case date, merchant, description
        case totalCost = "total_cost"
    }
}

enum OCRError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case server(String)
    case noTextContent
    case invalidJSON
    case unexpectedShape

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Anthropic API key set. Add one in Settings to scan receipts."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .server(let message):
            return message
        case .noTextContent:
            return "OCR extraction returned no text content."
        case .invalidJSON:
            return "OCR extraction returned invalid JSON."
        case .unexpectedShape:
            return "OCR extraction returned an unexpected shape."
        }
    }
}

/// Direct on-device client for Claude's Vision API — no backend involved,
/// per the standalone-architecture pivot (docs/plans/2026-07-23-ios-app.md).
/// Ports `backend/src/services/ocrService.js`'s exact model, prompt, and
/// JSON schema so extraction quality matches the web app; do not redesign
/// the prompt/schema independently of that file.
enum AnthropicVisionClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-opus-4-8"
    static let anthropicVersion = "2023-06-01"
    static let extractionPrompt = """
    This photo may contain one or more separate, distinct receipts. Identify EACH separate receipt in the image and extract its date, merchant name, total cost, and a brief description of the item(s) purchased as its own entry. Do not merge multiple receipts into one entry. If there is only one receipt, return a single entry. Give your best reasonable guess for any field that is not perfectly clear.
    """

    static func extractReceipts(imageData: Data, mediaType: String, session: URLSession = .shared) async throws -> [ExtractedReceipt] {
        guard let apiKey = APIKeyStore.load(), !apiKey.isEmpty else {
            throw OCRError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(imageData: imageData, mediaType: mediaType))

        let (data, response) = try await session.data(for: request)
        return try parseReceipts(from: data, response: response)
    }

    /// Exposed for unit testing without hitting the network.
    static func requestBody(imageData: Data, mediaType: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 4096,
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": receiptsSchema(),
                ],
            ],
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": ["type": "base64", "media_type": mediaType, "data": imageData.base64EncodedString()],
                    ],
                    ["type": "text", "text": extractionPrompt],
                ],
            ]],
        ]
    }

    /// Exposed for unit testing without hitting the network.
    static func parseReceipts(from data: Data, response: URLResponse) throws -> [ExtractedReceipt] {
        guard let http = response as? HTTPURLResponse else { throw OCRError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(AnthropicErrorBody.self, from: data))?.error.message
            throw OCRError.server(message ?? "Request failed with status \(http.statusCode).")
        }

        let messageResponse: MessagesAPIResponse
        do {
            messageResponse = try JSONDecoder().decode(MessagesAPIResponse.self, from: data)
        } catch {
            throw OCRError.invalidResponse
        }

        guard let textBlock = messageResponse.content.first(where: { $0.type == "text" }), let text = textBlock.text else {
            throw OCRError.noTextContent
        }
        guard let jsonData = text.data(using: .utf8) else {
            throw OCRError.invalidJSON
        }

        do {
            let parsed = try JSONDecoder().decode(ExtractedReceiptsResponse.self, from: jsonData)
            return parsed.receipts
        } catch {
            throw OCRError.unexpectedShape
        }
    }

    private static func receiptFieldsSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "date": ["type": "string", "description": "Receipt date in YYYY-MM-DD format"],
                "merchant": ["type": "string", "description": "Merchant or vendor name"],
                "total_cost": ["type": "number", "description": "Total amount charged, in dollars"],
                "description": ["type": "string", "description": "Brief description of the item(s) purchased"],
            ],
            "required": ["date", "merchant", "total_cost", "description"],
            "additionalProperties": false,
        ]
    }

    private static func receiptsSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": ["receipts": ["type": "array", "items": receiptFieldsSchema()]],
            "required": ["receipts"],
            "additionalProperties": false,
        ]
    }
}

struct MessagesAPIResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    let content: [ContentBlock]
}

struct ExtractedReceiptsResponse: Decodable {
    let receipts: [ExtractedReceipt]
}

struct AnthropicErrorBody: Decodable {
    struct ErrorDetail: Decodable { let message: String }
    let error: ErrorDetail
}
