import Foundation
import JerdManifest

/// The fixed names of a Jerd release: the public repository, the Sparkle Keychain account, the asset
/// names, the tag, and the feed branch. Installed apps depend on the repository and the feed URL.
enum ReleaseNames {
    static let repository = "jewei/jerd"
    /// The Keychain account of the Sparkle EdDSA private key. The key never leaves the Keychain.
    static let sparkleAccount = "dev.jerd.sparkle"
    static let architecture = "arm64"
    static let appIdentifier = "dev.jerd.app"
    static let cliIdentifier = "dev.jerd.cli"
    static let helperIdentifier = "dev.jerd.helper"

    /// The `origin` URLs that may receive a publication.
    static let originURLs = [
        "git@github.com:\(repository).git", "https://github.com/\(repository).git", "https://github.com/\(repository)",
    ]

    static var feedURL: URL {
        guard let url = URL(string: AppUpdateSettings.officialFeedURL) else { preconditionFailure("constant URL") }
        return url
    }

    static func tag(_ version: ReleaseVersion) -> String { "v\(version)" }
    static func diskImage(_ version: ReleaseVersion) -> String { "Jerd-\(version).dmg" }
    static func symbols(_ version: ReleaseVersion, build: Int) -> String { "Jerd-\(version)-\(build).dSYMs.zip" }
    static func feedBranch(_ version: ReleaseVersion) -> String { "release-feed/v\(version)" }
    static func releaseTitle(_ version: ReleaseVersion) -> String { "Jerd \(version)" }

    /// The public download URL of the disk image, which the feed item names.
    static func diskImageURL(_ version: ReleaseVersion) -> URL {
        let text = "https://github.com/\(repository)/releases/download/\(tag(version))/\(diskImage(version))"
        guard let url = URL(string: text) else { preconditionFailure("valid version text") }
        return url
    }
}
