import XCTest
@testable import ReceiptTracker

final class GoogleDriveUploaderTests: XCTestCase {
    // MARK: - multipartUploadRequest

    func testMultipartUploadRequestHasBearerAuthAndBoundaryContentType() {
        let request = GoogleDriveUploader.multipartUploadRequest(
            filename: "2026-08-05_Costco.jpg",
            fileData: Data("fake-jpeg-bytes".utf8),
            folderID: "folder123",
            accessToken: "tok_abc",
            boundary: "BOUNDARY123"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, GoogleDriveUploader.uploadEndpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok_abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/related; boundary=BOUNDARY123")
    }

    func testMultipartUploadRequestBodyContainsMetadataAndImageBytes() throws {
        let imageData = Data("fake-jpeg-bytes".utf8)
        let request = GoogleDriveUploader.multipartUploadRequest(
            filename: "2026-08-05_Costco.jpg",
            fileData: imageData,
            folderID: "folder123",
            accessToken: "tok_abc",
            boundary: "BOUNDARY123"
        )

        let body = try XCTUnwrap(request.httpBody)
        let bodyString = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(bodyString.contains("--BOUNDARY123"))
        XCTAssertTrue(bodyString.contains("\"name\":\"2026-08-05_Costco.jpg\""))
        XCTAssertTrue(bodyString.contains("\"parents\":[\"folder123\"]"))
        XCTAssertTrue(bodyString.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(body.range(of: imageData) != nil, "body should contain the raw image bytes")
        XCTAssertTrue(bodyString.hasSuffix("--BOUNDARY123--"))
    }

    // MARK: - parseFolderSearchResponse

    func testParseFolderSearchResponseReturnsIDWhenFolderFound() throws {
        let response = try makeHTTPResponse(status: 200)
        let data = Data(#"{"files":[{"id":"folder123","name":"ReceiptDrive"}]}"#.utf8)

        let id = try GoogleDriveUploader.parseFolderSearchResponse(from: data, response: response)
        XCTAssertEqual(id, "folder123")
    }

    func testParseFolderSearchResponseReturnsNilWhenNoFolderFound() throws {
        let response = try makeHTTPResponse(status: 200)
        let data = Data(#"{"files":[]}"#.utf8)

        let id = try GoogleDriveUploader.parseFolderSearchResponse(from: data, response: response)
        XCTAssertNil(id)
    }

    func testParseFolderSearchResponseThrowsServerErrorForNon2xxStatus() throws {
        let response = try makeHTTPResponse(status: 401)
        let data = Data(#"{"error":{"code":401,"message":"Invalid Credentials"}}"#.utf8)

        XCTAssertThrowsError(try GoogleDriveUploader.parseFolderSearchResponse(from: data, response: response)) { error in
            guard case GoogleDriveUploadError.server(let message) = error else {
                return XCTFail("Expected .server, got \(error)")
            }
            XCTAssertEqual(message, "Invalid Credentials")
        }
    }

    // MARK: - parseCreateFolderResponse

    func testParseCreateFolderResponseReturnsID() throws {
        let response = try makeHTTPResponse(status: 200)
        let data = Data(#"{"id":"newFolder456","name":"ReceiptDrive"}"#.utf8)

        let id = try GoogleDriveUploader.parseCreateFolderResponse(from: data, response: response)
        XCTAssertEqual(id, "newFolder456")
    }

    func testParseCreateFolderResponseThrowsInvalidResponseForMalformedJSON() throws {
        let response = try makeHTTPResponse(status: 200)
        let data = Data("not json".utf8)

        XCTAssertThrowsError(try GoogleDriveUploader.parseCreateFolderResponse(from: data, response: response)) { error in
            XCTAssertEqual(error as? GoogleDriveUploadError, .invalidResponse)
        }
    }

    // MARK: - parseUploadResponse

    func testParseUploadResponseReturnsFileOnSuccess() throws {
        let response = try makeHTTPResponse(status: 200)
        let data = Data(#"{"id":"file789","name":"2026-08-05_Costco.jpg"}"#.utf8)

        let file = try GoogleDriveUploader.parseUploadResponse(from: data, response: response)
        XCTAssertEqual(file.id, "file789")
    }

    func testParseUploadResponseThrowsServerErrorForNon2xxStatus() throws {
        let response = try makeHTTPResponse(status: 403)
        let data = Data(#"{"error":{"code":403,"message":"The user does not have sufficient permissions"}}"#.utf8)

        XCTAssertThrowsError(try GoogleDriveUploader.parseUploadResponse(from: data, response: response)) { error in
            guard case GoogleDriveUploadError.server(let message) = error else {
                return XCTFail("Expected .server, got \(error)")
            }
            XCTAssertEqual(message, "The user does not have sufficient permissions")
        }
    }

    // MARK: - summarize (bulk-result aggregation)

    func testSummarizeAllSucceeded() {
        XCTAssertEqual(GoogleDriveUploader.summarize(successCount: 5, totalCount: 5), "5 of 5 uploaded to Google Drive.")
    }

    func testSummarizePartialFailure() {
        XCTAssertEqual(
            GoogleDriveUploader.summarize(successCount: 4, totalCount: 5),
            "4 of 5 uploaded to Google Drive — 1 failed."
        )
    }

    func testSummarizeAllFailed() {
        XCTAssertEqual(
            GoogleDriveUploader.summarize(successCount: 0, totalCount: 3),
            "0 of 3 uploaded to Google Drive — 3 failed."
        )
    }

    // MARK: - Helpers

    private func makeHTTPResponse(status: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: GoogleDriveUploader.filesEndpoint, statusCode: status, httpVersion: nil, headerFields: nil))
    }

    // MARK: - PDF receipts

    func testReceiptWithPDFUploadsThePDF() throws {
        let date = DateOnly.date(from: "2026-08-05")!
        let pdf = try XCTUnwrap(DriveUploadItem.forReceipt(date: date, merchant: "Costco", fallbackID: "x", imageData: Data([1]), pdfData: Data([2])))
        XCTAssertEqual(pdf.filename, "2026-08-05_Costco.pdf")
        XCTAssertEqual(pdf.mimeType, "application/pdf")
        XCTAssertEqual(pdf.fileData, Data([2]))

        let photo = try XCTUnwrap(DriveUploadItem.forReceipt(date: date, merchant: "Costco", fallbackID: "x", imageData: Data([1]), pdfData: nil))
        XCTAssertEqual(photo.filename, "2026-08-05_Costco.jpg")
        XCTAssertEqual(photo.mimeType, "image/jpeg")
        XCTAssertNil(DriveUploadItem.forReceipt(date: date, merchant: nil, fallbackID: "x", imageData: nil, pdfData: nil))

        let request = GoogleDriveUploader.multipartUploadRequest(filename: pdf.filename, fileData: pdf.fileData, mimeType: pdf.mimeType, folderID: "f", accessToken: "t", boundary: "B")
        XCTAssertTrue(String(decoding: request.httpBody!, as: UTF8.self).contains("Content-Type: application/pdf"))
    }
}
