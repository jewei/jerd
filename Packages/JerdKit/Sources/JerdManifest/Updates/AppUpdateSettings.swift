import Foundation
import JerdFoundation

/// The validated Sparkle settings of a build: the one official feed URL and its Ed25519 key.
///
/// Installed apps depend on both values, so a build must carry exactly the official ones. The
/// app reads them from Info.plist (`SUFeedURL`, `SUPublicEDKey`); the release tool checks them the
/// same way, so one rule decides for both.
public struct AppUpdateSettings: Equatable, Sendable {
    /// The signed HTTPS feed of the public `jewei/jerd` repository.
    public static let officialFeedURL = "https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml"
    /// The base64 Ed25519 public key that verifies the feed and every update archive.
    public static let officialPublicKey = "FjYzr89ynpNrTtI8Me8zqA88YYJrRmloo4bj6dLbAJA="

    public let feedURL: URL
    /// The base64 text of the key, as Info.plist stores it.
    public let publicKey: String
    /// The 32 raw key bytes.
    public let publicKeyBytes: Data

    /// Validates the two Info.plist values.
    /// - Throws: `.unavailable` when a value is missing, `.invalid` when a value is malformed or not the official one.
    public init(feedURL: String?, publicKey: String?) throws {
        guard let feedURL, !feedURL.isEmpty else { throw JerdError.unavailable("This build has no app update feed.") }
        guard Self.isWellFormedFeed(feedURL), let url = URL(string: feedURL) else {
            throw JerdError.invalid("This build has an invalid app update feed.")
        }
        guard feedURL == Self.officialFeedURL else {
            throw JerdError.invalid("This build has an unexpected app update feed. Use the official Jerd feed.")
        }
        guard let publicKey, !publicKey.isEmpty else {
            throw JerdError.unavailable("This build has no app update verification key.")
        }
        guard let bytes = Data(base64Encoded: publicKey), bytes.count == 32 else {
            throw JerdError.invalid("This build has an invalid app update verification key.")
        }
        guard publicKey == Self.officialPublicKey else {
            throw JerdError.invalid("This build has an unexpected app update verification key.")
        }
        self.feedURL = url
        self.publicKey = publicKey
        publicKeyBytes = bytes
    }

    /// The official settings.
    public static func official() throws -> AppUpdateSettings {
        try AppUpdateSettings(feedURL: officialFeedURL, publicKey: officialPublicKey)
    }

    /// HTTPS, a host, no user, password, or fragment, and no white space. Unexpanded build settings fail here.
    static func isWellFormedFeed(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace), let components = URLComponents(string: text) else { return false }
        return components.scheme == "https" && !(components.host ?? "").isEmpty && components.user == nil
            && components.password == nil && components.fragment == nil && components.url != nil
    }
}
