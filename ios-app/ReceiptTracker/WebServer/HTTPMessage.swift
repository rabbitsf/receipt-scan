import Foundation

/// One parsed HTTP/1.1 request, as needed by Web Access over Wi-Fi.
struct HTTPRequest: Sendable {
    let method: String
    /// Percent-decoded path segments, e.g. `/api/receipts/categories/Snacks%20%26%20Co`
    /// → `["api", "receipts", "categories", "Snacks & Co"]`.
    let pathSegments: [String]
    let path: String
    let query: [String: String]
    /// Header names lowercased.
    let headers: [String: String]
    let body: Data

    var cookies: [String: String] {
        guard let header = headers["cookie"] else { return [:] }
        var result: [String: String] = [:]
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    /// Form fields from an `application/x-www-form-urlencoded` body.
    var formFields: [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: body, as: UTF8.self).replacingOccurrences(of: "+", with: "%20")
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] { result[item.name] = item.value ?? "" }
        return result
    }

    func jsonObject() -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

struct HTTPResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data

    init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])) ?? Data("null".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: data)
    }

    /// Same `{ error }` shape as the Express backend, which `frontend/src/api.js` reads.
    static func error(_ message: String, status: Int) -> HTTPResponse {
        json(["error": message], status: status)
    }

    static func html(_ text: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/html; charset=utf-8"], body: Data(text.utf8))
    }

    static func redirect(to location: String, headers extra: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: 303, headers: extra.merging(["Location": location]) { $1 })
    }

    static let noContent = HTTPResponse(status: 204)

    /// Full wire bytes. Every response closes the connection — simplest
    /// correct behavior for a small LAN server.
    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = "close"
        allHeaders["Cache-Control"] = allHeaders["Cache-Control"] ?? "no-store"
        for (name, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 303: return "See Other"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 429: return "Too Many Requests"
        case 502: return "Bad Gateway"
        default: return status < 400 ? "OK" : "Error"
        }
    }
}

enum HTTPRequestParser {
    enum Result: Sendable {
        case incomplete
        case complete(HTTPRequest)
        case invalid
        case tooLarge
    }

    /// Matches the Express upload limit (15 MB) plus multipart overhead.
    static let maxBodyBytes = 20 * 1024 * 1024
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    /// Parses `data` once it holds a full request (headers + `Content-Length`
    /// body). Call again with more bytes while it returns `.incomplete`.
    static func parse(_ data: Data, maxBodyBytes: Int = maxBodyBytes) -> Result {
        guard let headerEnd = data.range(of: headerTerminator) else {
            return data.count > 64 * 1024 ? .invalid : .incomplete
        }
        guard let headerText = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? -1
        guard contentLength >= 0 else { return .invalid }
        guard contentLength <= maxBodyBytes else { return .tooLarge }
        let bodyStart = headerEnd.upperBound
        guard data.endIndex - bodyStart >= contentLength else { return .incomplete }
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])

        let target = String(requestLine[1])
        guard let components = URLComponents(string: "http://host" + (target.hasPrefix("/") ? target : "/" + target)) else {
            return .invalid
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let segments = components.percentEncodedPath
            .split(separator: "/")
            .map { $0.removingPercentEncoding ?? String($0) }

        return .complete(HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            pathSegments: segments,
            path: components.path,
            query: query,
            headers: headers,
            body: body
        ))
    }
}

/// `multipart/form-data` body parsing, for `POST /api/receipts/upload`.
enum MultipartFormData {
    struct Part {
        let name: String
        let filename: String?
        let contentType: String?
        let data: Data
    }

    static func boundary(fromContentType contentType: String?) -> String? {
        guard let contentType, contentType.lowercased().hasPrefix("multipart/form-data") else { return nil }
        for parameter in contentType.split(separator: ";").dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, pair[0].lowercased() == "boundary" {
                return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }

    static func parse(_ body: Data, boundary: String) -> [Part] {
        let delimiter = Data("--\(boundary)".utf8)
        let headerTerminator = Data("\r\n\r\n".utf8)
        var parts: [Part] = []
        var searchStart = body.startIndex

        guard var current = body.range(of: delimiter, in: searchStart..<body.endIndex) else { return [] }
        while true {
            searchStart = current.upperBound
            guard let next = body.range(of: delimiter, in: searchStart..<body.endIndex) else { break }
            // Section between delimiters: "\r\n<headers>\r\n\r\n<data>\r\n"
            var section = body[searchStart..<next.lowerBound]
            if section.starts(with: Data("\r\n".utf8)) { section = section.dropFirst(2) }
            if section.count >= 2, section.suffix(2) == Data("\r\n".utf8) { section = section.dropLast(2) }
            if let headerEnd = section.range(of: headerTerminator),
               let headerText = String(data: section[section.startIndex..<headerEnd.lowerBound], encoding: .utf8) {
                var name: String?
                var filename: String?
                var contentType: String?
                for line in headerText.components(separatedBy: "\r\n") {
                    let lower = line.lowercased()
                    if lower.hasPrefix("content-disposition:") {
                        name = Self.parameter("name", in: line)
                        filename = Self.parameter("filename", in: line)
                    } else if lower.hasPrefix("content-type:") {
                        contentType = line.dropFirst("content-type:".count).trimmingCharacters(in: .whitespaces)
                    }
                }
                if let name {
                    parts.append(Part(name: name, filename: filename, contentType: contentType, data: Data(section[headerEnd.upperBound...])))
                }
            }
            current = next
        }
        return parts
    }

    private static func parameter(_ key: String, in line: String) -> String? {
        for piece in line.split(separator: ";") {
            let pair = piece.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, pair[0].lowercased() == key {
                return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }
}
