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
    case missingAPIKey(providerName: String)
    case invalidResponse
    case server(String)
    case noTextContent
    case invalidJSON
    case unexpectedShape

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let providerName):
            return "No \(providerName) API key set. Add one in Settings to scan receipts."
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

/// The provider-independent half of receipt OCR: ONE prompt, ONE output
/// schema and ONE decoder shared by every `VisionOCRClient`
/// (`AnthropicVisionClient`, `OpenAIVisionClient`, `GeminiVisionClient`), so
/// switching providers in Settings can never change what gets extracted.
/// Ports `backend/src/services/ocrService.js`'s prompt and schema; do not
/// redesign them independently of that file.
enum ReceiptExtraction {
    static let prompt = """
    This photo may contain one or more separate, distinct receipts. Identify EACH separate receipt in the image and extract its date, merchant name, total cost, and a brief description of the item(s) purchased as its own entry. Do not merge multiple receipts into one entry. If there is only one receipt, return a single entry. Give your best reasonable guess for any field that is not perfectly clear.
    """

    static func receiptFieldsSchema() -> [String: Any] {
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

    static func receiptsSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": ["receipts": ["type": "array", "items": receiptFieldsSchema()]],
            "required": ["receipts"],
            "additionalProperties": false,
        ]
    }

    /// Throws `OCRError.server` for non-2xx responses, using the provider's
    /// own error message when present — Anthropic, OpenAI and Gemini all
    /// report errors as `{"error": {"message": "..."}}`.
    static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw OCRError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ProviderErrorBody.self, from: data))?.error.message
            throw OCRError.server(message ?? "Request failed with status \(http.statusCode).")
        }
    }

    /// Decodes the model's structured-output text (already pulled out of the
    /// provider-specific response envelope) into receipts.
    static func decodeReceipts(fromJSONText text: String) throws -> [ExtractedReceipt] {
        guard let jsonData = text.data(using: .utf8) else {
            throw OCRError.invalidJSON
        }
        do {
            return try JSONDecoder().decode(ExtractedReceiptsResponse.self, from: jsonData).receipts
        } catch {
            throw OCRError.unexpectedShape
        }
    }
}

/// One provider's wire format: how to build the HTTP request and how to
/// find the model's JSON text in that provider's response. Everything else
/// (key lookup, model choice, sending) lives in `ReceiptExtractor`.
protocol VisionOCRClient {
    static func makeRequest(images: [Data], mediaType: String, model: String, apiKey: String) throws -> URLRequest
    static func parseReceipts(from data: Data, response: URLResponse) throws -> [ExtractedReceipt]
}

struct ExtractedReceiptsResponse: Decodable {
    let receipts: [ExtractedReceipt]
}

struct ProviderErrorBody: Decodable {
    struct ErrorDetail: Decodable { let message: String }
    let error: ErrorDetail
}
