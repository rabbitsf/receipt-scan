import Foundation

/// THE entry point for receipt OCR — every scan (camera/library photo or
/// imported PDF pages, via `ReceiptFormView.scanReceipt`) goes through here.
/// Looks up the provider chosen in Settings, its key and model, then hands
/// the provider-specific wire format to that provider's `VisionOCRClient`.
enum ReceiptExtractor {
    static func extractReceipts(
        images: [Data],
        mediaType: String,
        provider: OCRProvider = OCRSettings.selectedProvider(),
        session: URLSession = .shared
    ) async throws -> [ExtractedReceipt] {
        guard !images.isEmpty else {
            throw OCRError.invalidResponse
        }
        guard let apiKey = APIKeyStore.load(for: provider), !apiKey.isEmpty else {
            throw OCRError.missingAPIKey(providerName: provider.displayName)
        }

        let request = try provider.client.makeRequest(
            images: images,
            mediaType: mediaType,
            model: OCRSettings.effectiveModel(for: provider),
            apiKey: apiKey
        )
        let (data, response) = try await session.data(for: request)
        return try provider.client.parseReceipts(from: data, response: response)
    }
}
