import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed (status \(status))."
        }
    }
}

/// Minimal Keychain wrapper for the user's own OCR provider API keys — one
/// independent entry per `OCRProvider`, so switching providers in Settings
/// never loses a key. Stored on-device only — never logged, never sent
/// anywhere except directly to that provider's API host by
/// `ReceiptExtractor`. Standalone architecture means there's no backend to
/// hold these secrets server-side (see docs/plans/2026-07-23-ios-app.md's
/// pivot section for why).
enum APIKeyStore {
    /// The Anthropic entry keeps the exact service/account it had before
    /// multi-provider support, so existing installs keep their saved key.
    private static func identifiers(for provider: OCRProvider) -> (service: String, account: String) {
        switch provider {
        case .anthropic:
            return ("com.webreceipt.ReceiptTracker.anthropicAPIKey", "anthropicAPIKey")
        case .openai, .gemini:
            return ("com.webreceipt.ReceiptTracker.\(provider.rawValue)APIKey", "\(provider.rawValue)APIKey")
        }
    }

    static func save(_ key: String, for provider: OCRProvider) throws {
        delete(for: provider)
        guard let data = key.data(using: .utf8) else { return }
        let ids = identifiers(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ids.service,
            kSecAttrAccount as String: ids.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func load(for provider: OCRProvider) -> String? {
        let ids = identifiers(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ids.service,
            kSecAttrAccount as String: ids.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(for provider: OCRProvider) -> Bool {
        let ids = identifiers(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ids.service,
            kSecAttrAccount as String: ids.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
