import XCTest
@testable import ReceiptTracker

final class APIKeyStoreTests: XCTestCase {
    override func tearDown() {
        APIKeyStore.delete()
        super.tearDown()
    }

    func testSaveThenLoadRoundTrips() throws {
        try APIKeyStore.save("sk-ant-test-key-123")
        XCTAssertEqual(APIKeyStore.load(), "sk-ant-test-key-123")
    }

    func testSaveOverwritesPreviousValue() throws {
        try APIKeyStore.save("first-key")
        try APIKeyStore.save("second-key")
        XCTAssertEqual(APIKeyStore.load(), "second-key")
    }

    func testLoadReturnsNilWhenNoKeyStored() {
        APIKeyStore.delete()
        XCTAssertNil(APIKeyStore.load())
    }

    func testDeleteRemovesStoredKey() throws {
        try APIKeyStore.save("some-key")
        XCTAssertTrue(APIKeyStore.delete())
        XCTAssertNil(APIKeyStore.load())
    }
}
