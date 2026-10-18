import Foundation

struct ExtractedReceipt: Decodable, Equatable {
    let date: String
    let merchant: String
    let totalCost: Double
    let description: String
    /// Which numbered images (1 = first image sent) show this receipt — how
    /// a multi-receipt PDF is split into each receipt's own pages. Empty when
    /// the model didn't say.
    let pages: [Int]

    init(date: String, merchant: String, totalCost: Double, description: String, pages: [Int] = []) {
        self.date = date
        self.merchant = merchant
        self.totalCost = totalCost
        self.description = description
        self.pages = pages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        merchant = try container.decode(String.self, forKey: .merchant)
        totalCost = try container.decode(Double.self, forKey: .totalCost)
        description = try container.decode(String.self, forKey: .description)
        pages = (try? container.decodeIfPresent([Int].self, forKey: .pages)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case date, merchant, description, pages
        case totalCost = "total_cost"
    }
}

enum OCRError: LocalizedError, Equatable {
    case missingAPIKey(providerName: String)
    case consentRequired(providerName: String)
    case invalidResponse
    case server(String)
    case noTextContent
    case invalidJSON
    case unexpectedShape

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let providerName):
            return "No \(providerName) API key set. Add one in Settings to scan receipts."
        case .consentRequired(let providerName):
            return "Sending receipts to \(providerName) isn't allowed yet. Allow it in Settings → Receipt Scanning."
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
    /// Must stay identical to `EXTRACTION_PROMPT` in `ocrService.js`.
    static let prompt = """
    These images may contain one or more separate, distinct receipts. The images are numbered in the order given (Image 1, Image 2, and so on). A multi-page receipt spans several images; unrelated receipts are separate. Identify EACH separate receipt and extract its date, merchant name, total cost, and a brief description of the item(s) purchased as its own entry, along with the numbers of the images that show it. Do not merge multiple receipts into one entry. If there is only one receipt, return a single entry. Give your best reasonable guess for any field that is not perfectly clear.
    """

    /// Most output tokens a scan may produce. Many receipts in a long PDF
    /// need room; the model stops early when it's done.
    static let maxOutputTokens = 16_000

    /// Interleaves "Image N:" text labels before each image (Anthropic's
    /// recommended multi-image layout), then the prompt — so the model's
    /// `pages` numbers refer to these labels. Each client supplies how to
    /// build its own text and image blocks.
    static func labeledContent<Block>(images: [Data], text: (String) -> Block, image: (Data) -> Block) -> [Block] {
        var blocks: [Block] = []
        for (index, data) in images.enumerated() {
            blocks.append(text("Image \(index + 1):"))
            blocks.append(image(data))
        }
        blocks.append(text(prompt))
        return blocks
    }

    static func receiptFieldsSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "date": ["type": "string", "description": "Receipt date in YYYY-MM-DD format"],
                "merchant": ["type": "string", "description": "Merchant or vendor name"],
                "total_cost": ["type": "number", "description": "Total amount charged, in dollars"],
                "description": ["type": "string", "description": "Brief description of the item(s) purchased"],
                "pages": [
                    "type": "array",
                    "items": ["type": "integer"],
                    "description": "Numbers of the images that show this receipt (Image 1 = 1)",
                ],
            ],
            "required": ["date", "merchant", "total_cost", "description", "pages"],
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
