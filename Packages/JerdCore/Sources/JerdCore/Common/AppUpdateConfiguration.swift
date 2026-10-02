import Foundation

public struct AppUpdateConfiguration: Sendable, Equatable {
    public let feedURL: URL
    public let publicKey: String

    public init(feedURL: String?, publicKey: String?) throws {
        guard let feedURL, !feedURL.isEmpty else { throw ConfigurationError.missingFeed }
        guard let components = URLComponents(string: feedURL),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil,
              !feedURL.contains(where: \.isWhitespace), let url = components.url else {
            throw ConfigurationError.invalidFeed
        }
        guard let publicKey, !publicKey.isEmpty else { throw ConfigurationError.missingKey }
        guard let bytes = Data(base64Encoded: publicKey), bytes.count == 32 else {
            throw ConfigurationError.invalidKey
        }
        self.feedURL = url
        self.publicKey = publicKey
    }

    public enum ConfigurationError: Error, LocalizedError {
        case missingFeed, invalidFeed, missingKey, invalidKey

        public var errorDescription: String? {
            switch self {
            case .missingFeed: "This build has no app update feed."
            case .invalidFeed: "This build has an invalid app update feed."
            case .missingKey: "This build has no app update verification key."
            case .invalidKey: "This build has an invalid app update verification key."
            }
        }
    }
}
