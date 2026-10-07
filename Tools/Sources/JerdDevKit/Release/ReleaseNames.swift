import Foundation
import JerdManifest

/// The fixed names of a Jerd release: the public repository, the default team, the Sparkle Keychain
/// account, the asset names, the tag, and the CI check. Installed apps depend on the repository and
/// the feed URL.
enum ReleaseNames {
    static let repository = "jewei/jerd"
    /// The Apple team of every Jerd release.
    static let team = "4L4SS26L9J"
    static let notaryProfile = "notarytool"
    /// The Keychain account of the Sparkle EdDSA private key. The key never leaves the Keychain.
    static let sparkleAccount = "dev.jerd.sparkle"
    static let architecture = "arm64"
    static let appIdentifier = "dev.jerd.app"
    static let cliIdentifier = "dev.jerd.cli"
    static let helperIdentifier = "dev.jerd.helper"
    /// The branch that holds the feed that installed apps read.
    static let mainBranch = "main"
    /// The CI job that runs `./dev check`. A release needs its success for the source commit.
    static let checkName = "./dev check"

    /// The `origin` URLs that may receive a release.
    static let originURLs = [
        "git@github.com:\(repository).git", "https://github.com/\(repository).git", "https://github.com/\(repository)",
    ]

    static func tag(_ version: ReleaseVersion) -> String { "v\(version)" }
    static func diskImage(_ version: ReleaseVersion) -> String { "Jerd-\(version).dmg" }
    static func symbols(_ version: ReleaseVersion, build: Int) -> String { "Jerd-\(version)-\(build).dSYMs.zip" }
    static func releaseTitle(_ version: ReleaseVersion) -> String { "Jerd \(version)" }
    static func commitMessage(_ version: ReleaseVersion) -> String { "Release \(tag(version))" }

    /// The public download URL of the disk image, which the feed item names.
    static func diskImageURL(_ version: ReleaseVersion) -> URL {
        let text = "https://github.com/\(repository)/releases/download/\(tag(version))/\(diskImage(version))"
        guard let url = URL(string: text) else { preconditionFailure("valid version text") }
        return url
    }
}
