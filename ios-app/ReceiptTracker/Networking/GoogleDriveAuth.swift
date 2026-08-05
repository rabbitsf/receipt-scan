import Foundation
import GoogleSignIn
import UIKit

enum GoogleDriveAuthError: LocalizedError, Equatable {
    case notSignedIn
    case missingClientID
    case signInFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not connected to Google Drive. Connect in Settings first."
        case .missingClientID:
            return "Google Sign-In is not configured (missing GIDClientID in Info.plist)."
        case .signInFailed(let message):
            return message
        }
    }
}

/// Single canonical wrapper around GoogleSignIn-iOS (`GIDSignIn`) — every
/// call into that SDK goes through here, mirroring `APIKeyStore` being the
/// one place Keychain calls happen. `GoogleDriveUploader` only ever asks
/// this for an access token; it never touches `GIDSignIn` directly.
enum GoogleDriveAuth {
    /// Narrowest Drive scope that covers uploading files this app creates —
    /// does NOT grant access to the rest of the user's Drive, unlike the
    /// broader `drive`/`drive.readonly` scopes.
    private static let driveScope = "https://www.googleapis.com/auth/drive.file"

    static var isSignedIn: Bool {
        GIDSignIn.sharedInstance.currentUser != nil
    }

    static var signedInEmail: String? {
        GIDSignIn.sharedInstance.currentUser?.profile?.email
    }

    /// Call once at app launch — silently restores a previous session, if
    /// any, with no UI. Safe to call even if there's nothing to restore.
    static func restorePreviousSignIn() async {
        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { _, _ in
                continuation.resume()
            }
        }
    }

    /// Presents Google's sign-in UI and requests the Drive upload scope up
    /// front (rather than a separate scope-grant round trip afterward).
    @MainActor
    static func signIn(presenting viewController: UIViewController) async throws {
        try configureIfNeeded()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController,
                hint: nil,
                additionalScopes: [driveScope]
            ) { _, error in
                if let error {
                    continuation.resume(throwing: GoogleDriveAuthError.signInFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    /// Forwarded from `ReceiptTrackerApp`'s `.onOpenURL` — completes the
    /// OAuth redirect. Returns whether GoogleSignIn recognized/handled the
    /// URL (it may not, if it's a scheme collision with something else).
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// A valid, non-expired access token for Drive API calls — refreshes
    /// automatically if the cached one has expired. Throws `.notSignedIn`
    /// if there's no current session; callers (`GoogleDriveUploader`)
    /// should surface that as "connect in Settings first" rather than
    /// prompting sign-in inline, per this feature's confirmed design.
    static func accessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleDriveAuthError.notSignedIn
        }
        return try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: GoogleDriveAuthError.signInFailed(error.localizedDescription))
                } else if let token = refreshedUser?.accessToken.tokenString {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: GoogleDriveAuthError.notSignedIn)
                }
            }
        }
    }

    /// Validates the Client ID before ever calling into `GIDSignIn.signIn`.
    /// `GIDSignIn.sharedInstance` auto-loads `.configuration` from the
    /// `GIDClientID` Info.plist key at init time (confirmed by reading
    /// GoogleSignIn-iOS's own source — `GIDSignIn.m`'s initializer calls
    /// `configurationFromBundle:`), so `.configuration` is already
    /// non-nil by the time this runs even with an unedited placeholder
    /// value — checking `configuration == nil` alone would never catch
    /// that. The actual `clientID` string (whichever source it came from)
    /// has to be checked directly instead.
    private static func configureIfNeeded() throws {
        let clientID = GIDSignIn.sharedInstance.configuration?.clientID
            ?? (Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String)
        guard let clientID, !clientID.isEmpty, !clientID.hasPrefix("REPLACE_ME") else {
            throw GoogleDriveAuthError.missingClientID
        }
        if GIDSignIn.sharedInstance.configuration == nil {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }
}
