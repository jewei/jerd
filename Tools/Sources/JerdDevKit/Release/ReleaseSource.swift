import Foundation

/// The facts of the source commit that a release builds, read once by the preconditions. The release
/// commit changes exactly these files: the version file, the changelog, and the feed.
struct ReleaseSource: Equatable, Sendable {
    var commit: String
    /// The unreleased notes, which become the notes of the release.
    var notes: String
    var feed: Data
    var changelog: String
    var versionFile: XcconfigFile
}
