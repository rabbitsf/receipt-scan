import Foundation

enum GoogleDriveUploadError: LocalizedError, Equatable {
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        case .invalidResponse:
            return "Google Drive returned an unexpected response."
        }
    }
}

struct DriveFile: Decodable, Equatable {
    let id: String
    let name: String?
}

private struct DriveFileListResponse: Decodable {
    let files: [DriveFile]
}

private struct DriveErrorResponse: Decodable {
    struct ErrorDetail: Decodable { let message: String }
    let error: ErrorDetail
}

/// One receipt's file, ready to upload: its PDF when it came from a PDF
/// import, otherwise its photo.
struct DriveUploadItem {
    let filename: String
    let fileData: Data
    var mimeType = "image/jpeg"

    /// THE rule for what a receipt uploads to Drive (single and bulk).
    /// nil when it has neither a PDF nor a photo.
    static func forReceipt(date: Date, merchant: String?, fallbackID: String, imageData: Data?, pdfData: Data?) -> DriveUploadItem? {
        if let pdfData {
            return DriveUploadItem(filename: DriveUploadFilename.make(date: date, merchant: merchant, fallbackID: fallbackID, fileExtension: "pdf"),
                                   fileData: pdfData, mimeType: "application/pdf")
        }
        guard let imageData else { return nil }
        return DriveUploadItem(filename: DriveUploadFilename.make(date: date, merchant: merchant, fallbackID: fallbackID), fileData: imageData)
    }
}

/// Result of a best-effort bulk upload — every item is attempted
/// independently (per this feature's confirmed design), so a summary is
/// reported rather than an all-or-nothing outcome.
struct DriveBulkUploadResult {
    let successCount: Int
    let totalCount: Int

    var summary: String {
        GoogleDriveUploader.summarize(successCount: successCount, totalCount: totalCount)
    }
}

/// Uploads receipt photos to a dedicated "ReceiptDrive" folder in the
/// user's Google Drive, created on first use (see `ensureFolder`). All
/// Drive REST calls are plain `URLSession` requests — no additional Drive
/// SDK beyond `GoogleSignIn-iOS` (which `GoogleDriveAuth` wraps for the
/// access token), per this feature's confirmed design.
enum GoogleDriveUploader {
    static let filesEndpoint = URL(string: "https://www.googleapis.com/drive/v3/files")!
    static let uploadEndpoint = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
    static let folderName = "ReceiptDrive"
    static let folderMimeType = "application/vnd.google-apps.folder"

    /// Not a secret — just remembers which Drive folder to upload into, so
    /// `ensureFolder` doesn't have to search/create on every upload.
    private static let folderIDDefaultsKey = "com.webreceipt.ReceiptTracker.driveFolderID"

    // MARK: - Bulk / single upload orchestration

    /// Uploads every item independently — one item's failure doesn't stop
    /// the rest (best-effort, per this feature's confirmed design). The
    /// access token and folder are resolved once up front and reused for
    /// all items.
    static func uploadAll(_ items: [DriveUploadItem], session: URLSession = .shared) async throws -> DriveBulkUploadResult {
        let accessToken = try await GoogleDriveAuth.accessToken()
        let folderID = try await ensureFolder(accessToken: accessToken, session: session)

        var successCount = 0
        for item in items {
            do {
                try await upload(item, folderID: folderID, accessToken: accessToken, session: session)
                successCount += 1
            } catch {
                // Best-effort: one item's failure doesn't stop the rest —
                // the caller sees the shortfall via the returned summary.
            }
        }
        return DriveBulkUploadResult(successCount: successCount, totalCount: items.count)
    }

    /// Convenience for the single-photo entry point (`ReceiptImageView`) —
    /// same underlying path as `uploadAll`, just unwraps the one-item
    /// result into a thrown error on failure.
    static func uploadOne(_ item: DriveUploadItem, session: URLSession = .shared) async throws {
        let result = try await uploadAll([item], session: session)
        guard result.successCount == 1 else {
            throw GoogleDriveUploadError.invalidResponse
        }
    }

    /// Exposed for unit testing without hitting the network.
    static func summarize(successCount: Int, totalCount: Int) -> String {
        guard successCount < totalCount else {
            return "\(totalCount) of \(totalCount) uploaded to Google Drive."
        }
        return "\(successCount) of \(totalCount) uploaded to Google Drive — \(totalCount - successCount) failed."
    }

    // MARK: - Folder ensure/create

    static var cachedFolderID: String? {
        get { UserDefaults.standard.string(forKey: folderIDDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: folderIDDefaultsKey) }
    }

    /// Returns the app's Drive folder ID: the cached one if present,
    /// otherwise a Drive search for an existing "ReceiptDrive" folder
    /// (covers a reinstall or a cleared cache finding a folder from a
    /// previous session), only creating a new one if neither is found.
    static func ensureFolder(accessToken: String, session: URLSession = .shared) async throws -> String {
        if let cached = cachedFolderID {
            return cached
        }
        if let found = try await findFolder(accessToken: accessToken, session: session) {
            cachedFolderID = found
            return found
        }
        let created = try await createFolder(accessToken: accessToken, session: session)
        cachedFolderID = created
        return created
    }

    private static func findFolder(accessToken: String, session: URLSession) async throws -> String? {
        var components = URLComponents(url: filesEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "name = '\(folderName)' and mimeType = '\(folderMimeType)' and trashed = false"),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        return try parseFolderSearchResponse(from: data, response: response)
    }

    /// Exposed for unit testing without hitting the network.
    static func parseFolderSearchResponse(from data: Data, response: URLResponse) throws -> String? {
        try validate(data: data, response: response)
        guard let decoded = try? JSONDecoder().decode(DriveFileListResponse.self, from: data) else {
            throw GoogleDriveUploadError.invalidResponse
        }
        return decoded.files.first?.id
    }

    private static func createFolder(accessToken: String, session: URLSession) async throws -> String {
        var request = URLRequest(url: filesEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": folderName, "mimeType": folderMimeType])
        let (data, response) = try await session.data(for: request)
        return try parseCreateFolderResponse(from: data, response: response)
    }

    /// Exposed for unit testing without hitting the network.
    static func parseCreateFolderResponse(from data: Data, response: URLResponse) throws -> String {
        try validate(data: data, response: response)
        guard let decoded = try? JSONDecoder().decode(DriveFile.self, from: data) else {
            throw GoogleDriveUploadError.invalidResponse
        }
        return decoded.id
    }

    // MARK: - File upload

    private static func upload(_ item: DriveUploadItem, folderID: String, accessToken: String, session: URLSession) async throws {
        let boundary = UUID().uuidString
        let request = multipartUploadRequest(filename: item.filename, fileData: item.fileData, mimeType: item.mimeType, folderID: folderID, accessToken: accessToken, boundary: boundary)
        let (data, response) = try await session.data(for: request)
        _ = try parseUploadResponse(from: data, response: response)
    }

    /// Exposed for unit testing without hitting the network. Drive v3's
    /// "multipart upload" format: one `application/json` part with the
    /// file's metadata (name + parent folder), one part with the raw image
    /// bytes.
    static func multipartUploadRequest(filename: String, fileData: Data, mimeType: String = "image/jpeg", folderID: String, accessToken: String, boundary: String) -> URLRequest {
        var request = URLRequest(url: uploadEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let metadataJSON = (try? JSONSerialization.data(withJSONObject: ["name": filename, "parents": [folderID]])) ?? Data()

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)

        request.httpBody = body
        return request
    }

    /// Exposed for unit testing without hitting the network.
    static func parseUploadResponse(from data: Data, response: URLResponse) throws -> DriveFile {
        try validate(data: data, response: response)
        guard let decoded = try? JSONDecoder().decode(DriveFile.self, from: data) else {
            throw GoogleDriveUploadError.invalidResponse
        }
        return decoded
    }

    // MARK: - Shared response validation

    private static func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw GoogleDriveUploadError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DriveErrorResponse.self, from: data))?.error.message
            throw GoogleDriveUploadError.server(message ?? "Request failed with status \(http.statusCode).")
        }
    }
}
