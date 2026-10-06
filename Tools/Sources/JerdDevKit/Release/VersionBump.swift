import Foundation
import JerdFoundation

/// `./dev release bump`: sets the next version in `Configuration/Version.xcconfig` and moves the
/// unreleased notes of `CHANGELOG.md` under that version. It does not commit: the change goes through
/// a normal pull request before `prepare`, so the notarized app is built from the exact commit that
/// the release tag names (fixes spec G 8.1 #6 for the version change, #11, and #12).
struct VersionBump: Sendable {
    let environment: ReleaseEnvironment

    /// - Returns: the changed files, relative to the repository.
    @discardableResult
    func run(version: ReleaseVersion, build: Int) throws -> [String] {
        let files = ReleaseSourceFiles(repository: environment.repository)
        var versionFile = try files.versionFile()
        let current = try files.version()
        let feed = try files.verifiedFeed()
        try VersionRules.checkBump(version: version, build: build, current: current, items: feed.appcast.items)
        let date = ReleaseNotes.dateText(environment.clock.now())
        let changelog = try ReleaseNotes.promoted(files.changelog(), version: version.text, date: date)
        try versionFile.set(ReleaseSourceFiles.marketingVersion, to: version.text)
        try versionFile.set(ReleaseSourceFiles.buildVersion, to: String(build))
        let repository = environment.repository
        try AtomicFile.write(Data(versionFile.text.utf8), to: repository.versionFile, durability: .standard)
        try AtomicFile.write(Data(changelog.utf8), to: repository.changelog, durability: .standard)
        let changed = [repository.versionFile, repository.changelog].map(repository.relativePath(of:))
        environment.console.success("Set version \(version) (\(build)) and the release notes of \(date).")
        environment.console.detail(
            "Commit \(changed.joined(separator: " and ")) in a pull request. Prepare the release after it merges.")
        return changed
    }
}
