import Foundation
import SwiftData
import UIKit

/// THE on/off switch for Web Access over Wi-Fi (Settings → Web Access).
/// While on, a computer on the same Wi-Fi can open `http://<phone-ip>:8080`,
/// enter the code shown in Settings, and use the bundled React web app
/// (`WebApp/`, built by `npm run build:ios-web`) on this phone's receipts.
///
/// Request flow: code check (`WebAccessGate`) → `/api/*` (`WebAPIRouter`)
/// → otherwise a file from `WebApp/` (unknown paths get `index.html`).
/// Off by default on every launch.
@MainActor
final class WebAccessServer: ObservableObject {
    static let shared = WebAccessServer()
    static let port: UInt16 = 8080

    /// What the Settings toggle shows: on from `start` until `stop`.
    @Published private(set) var isEnabled = false
    /// The port is actually open (false briefly while starting or after a failure).
    @Published private(set) var isRunning = false
    @Published private(set) var accessCode: String?
    @Published private(set) var errorMessage: String?

    private var server: WebHTTPServer?
    private var gate = WebAccessGate()
    private var router: WebAPIRouter?
    private var context: ModelContext?
    private let webRoot = Bundle.main.url(forResource: "WebApp", withExtension: nil)
    private let uploadsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("WebAccessUploads", isDirectory: true)
    private var foregroundObserver: NSObjectProtocol?

    /// `http://<Wi-Fi address>:8080`, or nil when the phone has no Wi-Fi address.
    var address: String? {
        LocalNetworkAddress.wifiIPv4().map { "http://\($0):\(Self.port)" }
    }

    func start(context: ModelContext) {
        guard server == nil else { return }
        self.context = context
        isEnabled = true
        gate = WebAccessGate()
        router = WebAPIRouter(context: context, uploadsDirectory: uploadsDirectory)
        accessCode = gate.code
        errorMessage = nil
        startListener()
        UIApplication.shared.isIdleTimerDisabled = true

        // iOS pauses the app (and its listener) in the background; reopen
        // the port when the user comes back. Code and sign-ins are kept.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.server != nil else { return }
                self.server?.stop()
                self.startListener()
            }
        }
    }

    func stop() {
        server?.stop()
        server = nil
        router = nil
        isEnabled = false
        isRunning = false
        accessCode = nil
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        foregroundObserver = nil
        UIApplication.shared.isIdleTimerDisabled = false
        try? FileManager.default.removeItem(at: uploadsDirectory)
    }

    private func startListener() {
        let server = WebHTTPServer(port: Self.port) { request in
            await WebAccessServer.shared.respond(to: request)
        }
        do {
            try server.start { [weak self] state in
                guard let self, self.server === server else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.errorMessage = nil
                case .failed(let message):
                    self.isRunning = false
                    self.errorMessage = "Couldn't start the server: \(message)"
                case .stopped:
                    self.isRunning = false
                }
            }
            self.server = server
        } catch {
            errorMessage = "Couldn't start the server: \(error.localizedDescription)"
        }
    }

    func respond(to request: HTTPRequest) async -> HTTPResponse {
        let isAPI = request.pathSegments.first == "api"

        if request.path == "/login" {
            guard request.method == "POST" else { return .redirect(to: "/") }
            switch gate.logIn(code: request.formFields["code"] ?? "") {
            case .success(let token):
                return .redirect(to: "/", headers: ["Set-Cookie": WebAccessGate.sessionCookie(token)])
            case .wrongCode(let attemptsLeft):
                return .html(WebAccessGate.codePage(message: "Wrong code. \(attemptsLeft) tr\(attemptsLeft == 1 ? "y" : "ies") left."), status: 401)
            case .locked:
                return .html(WebAccessGate.codePage(message: Self.lockedMessage), status: 429)
            }
        }

        guard gate.decide(request) == .allowed else {
            if isAPI { return .error("Enter the access code first", status: 401) }
            return .html(WebAccessGate.codePage(message: gate.isLocked ? Self.lockedMessage : nil))
        }

        if isAPI {
            guard let router else { return .error("Server is stopping", status: 503) }
            return await router.handle(request)
        }
        return staticFile(request)
    }

    private static let lockedMessage = "Too many wrong codes. Turn Web Access off and on in the iPhone app to get a new code."

    private func staticFile(_ request: HTTPRequest) -> HTTPResponse {
        guard request.method == "GET" || request.method == "HEAD", let webRoot else {
            return .error("Not found", status: 404)
        }
        let segments = request.pathSegments
        guard !segments.contains(where: { $0 == ".." || $0.hasPrefix(".") }) else { return .error("Not found", status: 404) }

        var fileURL = segments.reduce(webRoot) { $0.appendingPathComponent($1) }
        var isDirectory: ObjCBool = false
        if segments.isEmpty || !FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) || isDirectory.boolValue {
            // The React app has no router, so any unknown page is the app itself.
            guard segments.last?.contains(".") != true else { return .error("Not found", status: 404) }
            fileURL = webRoot.appendingPathComponent("index.html")
        }
        guard let data = try? Data(contentsOf: fileURL) else { return .error("Not found", status: 404) }
        let isHashedAsset = segments.first == "assets"
        return HTTPResponse(status: 200, headers: [
            "Content-Type": Self.mimeType(for: fileURL.pathExtension),
            "Cache-Control": isHashedAsset ? "public, max-age=31536000, immutable" : "no-store",
        ], body: request.method == "HEAD" ? Data() : data)
    }

    static func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "ico": return "image/x-icon"
        case "json", "map": return "application/json"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }
}

/// The phone's IPv4 address on Wi-Fi (`en0`), shown in Settings.
enum LocalNetworkAddress {
    static func wifiIPv4() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}
