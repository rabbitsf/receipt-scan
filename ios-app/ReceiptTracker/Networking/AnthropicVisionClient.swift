import Foundation

/// Direct on-device client for Claude's Vision API — no backend involved,
/// per the standalone-architecture pivot (docs/plans/2026-07-23-ios-app.md).
/// Only the Anthropic wire format lives here; the prompt/schema are shared
/// with the other providers via `ReceiptExtraction`, and key lookup/model
/// choice/sending go through `ReceiptExtractor`.
///
/// `images` may hold more than one image — e.g. every rendered page of
/// an imported multi-page PDF — sent together in one request so the
/// model can reason across all of them at once. The response schema
/// already returns an *array* of receipts regardless of image count,
/// so this naturally covers both "these pages are one receipt" (array
/// of length 1) and "these pages are actually separate receipts, e.g.
/// a scanned stack" (array of length >1, which flows into the same
/// review-queue mechanism a multi-receipt photo already uses) — no
/// separate code path needed for either case.
enum AnthropicVisionClient: VisionOCRClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let anthropicVersion = "2023-06-01"

    static func makeRequest(images: [Data], mediaType: String, model: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(images: images, mediaType: mediaType, model: model))
        return request
    }

    /// Exposed for unit testing without hitting the network.
    static func requestBody(images: [Data], mediaType: String, model: String) -> [String: Any] {
        let content: [[String: Any]] = ReceiptExtraction.labeledContent(
            images: images,
            text: { ["type": "text", "text": $0] },
            image: { ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": $0.base64EncodedString()]] }
        )
        return [
            "model": model,
            "max_tokens": ReceiptExtraction.maxOutputTokens,
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": ReceiptExtraction.receiptsSchema(),
                ],
            ],
            "messages": [[
                "role": "user",
                "content": content,
            ]],
        ]
    }

    /// Exposed for unit testing without hitting the network.
    static func parseReceipts(from data: Data, response: URLResponse) throws -> [ExtractedReceipt] {
        try ReceiptExtraction.validateHTTPResponse(response, data: data)

        let messageResponse: MessagesAPIResponse
        do {
            messageResponse = try JSONDecoder().decode(MessagesAPIResponse.self, from: data)
        } catch {
            throw OCRError.invalidResponse
        }

        guard let textBlock = messageResponse.content.first(where: { $0.type == "text" }), let text = textBlock.text else {
            throw OCRError.noTextContent
        }
        return try ReceiptExtraction.decodeReceipts(fromJSONText: text)
    }
}

struct MessagesAPIResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    let content: [ContentBlock]
}
