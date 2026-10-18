import XCTest
@testable import ReceiptTracker

final class WebHTTPTests: XCTestCase {
    private func request(_ text: String, body: Data = Data()) -> HTTPRequestParser.Result {
        HTTPRequestParser.parse(Data(text.utf8) + body)
    }

    func testParsesRequestLineQueryHeadersAndDecodedPath() throws {
        let result = request("GET /api/receipts/categories/Snacks%20%26%20Co?year=2026&q=a%20b HTTP/1.1\r\nHost: x\r\nCookie: a=1; rt_session=abc\r\n\r\n")
        guard case .complete(let req) = result else { return XCTFail("expected complete, got \(result)") }
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.pathSegments, ["api", "receipts", "categories", "Snacks & Co"])
        XCTAssertEqual(req.query["year"], "2026")
        XCTAssertEqual(req.query["q"], "a b")
        XCTAssertEqual(req.headers["host"], "x")
        XCTAssertEqual(req.cookies["rt_session"], "abc")
    }

    func testWaitsForFullBody() {
        guard case .incomplete = request("POST /x HTTP/1.1\r\nContent-Length: 10\r\n\r\n12345") else { return XCTFail() }
        guard case .incomplete = request("POST /x HTTP/1.1\r\nContent-Le") else { return XCTFail() }
        guard case .complete(let req) = request("POST /x HTTP/1.1\r\nContent-Length: 5\r\n\r\n12345") else { return XCTFail() }
        XCTAssertEqual(String(decoding: req.body, as: UTF8.self), "12345")
    }

    func testRejectsOversizedAndMalformedRequests() {
        guard case .tooLarge = HTTPRequestParser.parse(Data("POST /x HTTP/1.1\r\nContent-Length: 100\r\n\r\n".utf8), maxBodyBytes: 10) else { return XCTFail() }
        guard case .invalid = request("NONSENSE\r\n\r\n") else { return XCTFail() }
    }

    func testFormFieldsDecodePlusAndPercent() throws {
        guard case .complete(let req) = request("POST /login HTTP/1.1\r\nContent-Length: 16\r\n\r\ncode=12+3%2634&x") else { return XCTFail() }
        XCTAssertEqual(req.formFields["code"], "12 3&34")
    }

    func testMultipartParsesFilePart() {
        let boundary = "----WebKitFormBoundaryABC"
        let body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"r.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)
            + Data([0x89, 0x50, 0x0D, 0x0A, 0x00])
            + Data("\r\n--\(boundary)--\r\n".utf8)
        XCTAssertEqual(MultipartFormData.boundary(fromContentType: "multipart/form-data; boundary=\(boundary)"), boundary)
        let parts = MultipartFormData.parse(body, boundary: boundary)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first?.name, "image")
        XCTAssertEqual(parts.first?.filename, "r.png")
        XCTAssertEqual(parts.first?.contentType, "image/png")
        XCTAssertEqual(parts.first?.data, Data([0x89, 0x50, 0x0D, 0x0A, 0x00]))
    }

    func testResponseSerializationIncludesLengthAndClose() {
        let text = String(decoding: HTTPResponse.json(["ok": true]).serialized(), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 11\r\n"))
        XCTAssertTrue(text.contains("Connection: close\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n{\"ok\":true}"))
    }

    // MARK: - Access code

    private func requestWithCookie(_ token: String?) -> HTTPRequest {
        let cookie = token.map { "Cookie: \(WebAccessGate.cookieName)=\($0)\r\n" } ?? ""
        guard case .complete(let req) = request("GET / HTTP/1.1\r\n\(cookie)\r\n") else { fatalError() }
        return req
    }

    func testRandomCodeIsFourDigits() {
        for _ in 0..<50 {
            XCTAssertNotNil(WebAccessGate.randomCode().wholeMatch(of: /\d{4}/))
        }
    }

    func testCorrectCodeGivesSessionThatIsAllowed() {
        var gate = WebAccessGate(code: "0420")
        XCTAssertEqual(gate.decide(requestWithCookie(nil)), .needsCode)
        guard case .success(let token) = gate.logIn(code: "0420") else { return XCTFail() }
        XCTAssertEqual(gate.decide(requestWithCookie(token)), .allowed)
        XCTAssertEqual(gate.decide(requestWithCookie("forged")), .needsCode)
    }

    func testLocksAfterFiveWrongCodes() {
        var gate = WebAccessGate(code: "0420")
        for left in stride(from: 4, through: 1, by: -1) {
            XCTAssertEqual(gate.logIn(code: "1111"), .wrongCode(attemptsLeft: left))
        }
        XCTAssertEqual(gate.logIn(code: "1111"), .locked)
        XCTAssertEqual(gate.logIn(code: "0420"), .locked, "even the right code is refused once locked")
    }
}
