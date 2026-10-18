import Foundation

/// Public web pages the app links to. The privacy policy lives in the repo
/// (`PRIVACY.md`) — App Store Connect's privacy policy URL must be the same.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://github.com/rabbitsf/receipt-scan/blob/main/PRIVACY.md")!
}
