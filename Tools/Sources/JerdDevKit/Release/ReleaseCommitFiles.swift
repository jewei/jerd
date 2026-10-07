import Foundation

/// The new content of the three files that the release commit changes. Pure: the version file gets
/// the version and build, the changelog gets the unreleased notes under the version and date, and the
/// feed is the signed candidate feed.
struct ReleaseCommitFiles: Equatable, Sendable {
    static let versionPath = "Configuration/Version.xcconfig"
    static let changelogPath = "CHANGELOG.md"
    static let feedPath = "appcast.xml"
    static let paths = [versionPath, changelogPath, feedPath]

    var versionFile: String
    var changelog: String
    var feed: Data

    init(source: ReleaseSource, feed: Data, version: ReleaseVersion, build: Int, date: Date) throws {
        var file = source.versionFile
        try file.set(ReleaseSourceFiles.marketingVersion, to: version.text)
        try file.set(ReleaseSourceFiles.buildVersion, to: String(build))
        versionFile = file.text
        changelog = try ReleaseNotes.promoted(
            source.changelog, version: version.text, date: ReleaseNotes.dateText(date))
        self.feed = feed
    }
}
