import XCTest
@testable import ReceiptTracker

final class APIKeyStoreTests: XCTestCase {
    override func tearDown() {
        OCRProvider.allCases.forEach { APIKeyStore.delete(for: $0) }
        super.tearDown()
    }

    func testSaveThenLoadRoundTrips() throws {
        try APIKeyStore.save("sk-ant-test-key-123", for: .anthropic)
        XCTAssertEqual(APIKeyStore.load(for: .anthropic), "sk-ant-test-key-123")
    }

    func testSaveOverwritesPreviousValue() throws {
        try APIKeyStore.save("first-key", for: .anthropic)
        try APIKeyStore.save("second-key", for: .anthropic)
        XCTAssertEqual(APIKeyStore.load(for: .anthropic), "second-key")
    }

    func testLoadReturnsNilWhenNoKeyStored() {
        APIKeyStore.delete(for: .anthropic)
        XCTAssertNil(APIKeyStore.load(for: .anthropic))
    }

    func testDeleteRemovesStoredKey() throws {
        try APIKeyStore.save("some-key", for: .anthropic)
        XCTAssertTrue(APIKeyStore.delete(for: .anthropic))
        XCTAssertNil(APIKeyStore.load(for: .anthropic))
    }

    /// Switching providers in Settings must never lose another provider's key.
    func testKeysAreStoredIndependentlyPerProvider() throws {
        try APIKeyStore.save("anthropic-key", for: .anthropic)
        try APIKeyStore.save("openai-key", for: .openai)
        try APIKeyStore.save("gemini-key", for: .gemini)

        XCTAssertEqual(APIKeyStore.load(for: .anthropic), "anthropic-key")
        XCTAssertEqual(APIKeyStore.load(for: .openai), "openai-key")
        XCTAssertEqual(APIKeyStore.load(for: .gemini), "gemini-key")

        APIKeyStore.delete(for: .openai)
        XCTAssertNil(APIKeyStore.load(for: .openai))
        XCTAssertEqual(APIKeyStore.load(for: .anthropic), "anthropic-key")
        XCTAssertEqual(APIKeyStore.load(for: .gemini), "gemini-key")
    }

    /// Keys saved before multi-provider support used this exact Keychain
    /// service/account; existing installs must keep scanning with them.
    func testAnthropicKeyUsesPreMultiProviderKeychainIdentifiers() throws {
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.webreceipt.ReceiptTracker.anthropicAPIKey",
            kSecAttrAccount as String: "anthropicAPIKey",
            kSecValueData as String: Data("legacy-key".utf8),
        ]
        APIKeyStore.delete(for: .anthropic)
        XCTAssertEqual(SecItemAdd(legacyQuery as CFDictionary, nil), errSecSuccess)

        XCTAssertEqual(APIKeyStore.load(for: .anthropic), "legacy-key")
    }
}
