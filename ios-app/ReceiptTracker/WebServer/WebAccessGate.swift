import Foundation

/// The 4-digit code that protects Web Access over Wi-Fi. A new code is made
/// each time the server starts and shown on the phone; a browser that enters
/// it gets a session cookie. After `maxFailedAttempts` wrong codes, sign-in is
/// locked until the server is restarted (which also makes a new code).
struct WebAccessGate {
    static let cookieName = "rt_session"
    static let maxFailedAttempts = 5

    enum Decision: Equatable {
        case allowed
        /// Not signed in: pages get the code page, `/api` gets 401.
        case needsCode
    }

    enum LoginResult: Equatable {
        case success(sessionToken: String)
        case wrongCode(attemptsLeft: Int)
        case locked
    }

    let code: String
    private(set) var failedAttempts = 0
    private var sessions: Set<String> = []

    init(code: String = WebAccessGate.randomCode()) {
        self.code = code
    }

    static func randomCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }

    var isLocked: Bool { failedAttempts >= Self.maxFailedAttempts }

    func decide(_ request: HTTPRequest) -> Decision {
        guard let token = request.cookies[Self.cookieName], sessions.contains(token) else { return .needsCode }
        return .allowed
    }

    mutating func logIn(code entered: String) -> LoginResult {
        guard !isLocked else { return .locked }
        guard entered.trimmingCharacters(in: .whitespaces) == code else {
            failedAttempts += 1
            return isLocked ? .locked : .wrongCode(attemptsLeft: Self.maxFailedAttempts - failedAttempts)
        }
        let token = UUID().uuidString + UUID().uuidString
        sessions.insert(token)
        return .success(sessionToken: token)
    }

    static func sessionCookie(_ token: String) -> String {
        "\(cookieName)=\(token); Path=/; HttpOnly; SameSite=Strict"
    }

    /// Small standalone page (the React app isn't loaded until signed in).
    static func codePage(message: String? = nil) -> String {
        let messageHTML = message.map { "<p class=\"msg\">\(escapeHTML($0))</p>" } ?? ""
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Receipt Tracker</title>
        <style>
          :root { color-scheme: light dark; --bg: #f5f5f7; --card: #fff; --text: #1d1d1f; --muted: #6e6e73; --accent: #0a84ff; --err: #d70015; }
          @media (prefers-color-scheme: dark) { :root { --bg: #000; --card: #1c1c1e; --text: #f5f5f7; --muted: #98989d; --err: #ff6961; } }
          body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg); color: var(--text);
                 font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
          form { background: var(--card); padding: 32px; border-radius: 16px; width: min(320px, calc(100vw - 32px)); box-sizing: border-box;
                 box-shadow: 0 4px 24px rgba(0,0,0,.08); text-align: center; }
          h1 { font-size: 20px; margin: 0 0 8px; }
          p { color: var(--muted); font-size: 14px; margin: 0 0 20px; line-height: 1.4; }
          input { font-size: 28px; letter-spacing: 12px; text-align: center; width: 100%; box-sizing: border-box; padding: 10px;
                  border: 1px solid var(--muted); border-radius: 10px; background: transparent; color: var(--text); }
          button { margin-top: 16px; width: 100%; padding: 12px; font-size: 16px; border: 0; border-radius: 10px; background: var(--accent); color: #fff; cursor: pointer; }
          .msg { color: var(--err); margin: 12px 0 0; }
        </style>
        </head>
        <body>
        <form method="post" action="/login">
          <h1>Receipt Tracker</h1>
          <p>Enter the 4-digit code shown on your iPhone in Settings → Web Access over Wi-Fi.</p>
          <input name="code" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" autocomplete="off" autofocus required aria-label="Access code">
          <button type="submit">Open</button>
          \(messageHTML)
        </form>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
