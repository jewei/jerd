import JerdManifest

/// The version rules of a release. Sparkle offers an update only for a higher build, and users compare
/// marketing versions, so both must grow with every release.
enum VersionRules {
    /// The new build and version exceed every item of the committed feed. An empty feed is valid.
    static func checkFeed(version: ReleaseVersion, build: Int, items: [AppcastItem]) throws {
        for item in items {
            guard let published = ReleaseVersion.build(item.bundleVersion) else {
                throw DevFailure.checkFailed("The feed has an item with the build \(item.bundleVersion).")
            }
            guard build > published else {
                throw DevFailure.checkFailed("BUILD \(build) must exceed the build \(published) in appcast.xml.")
            }
            guard let short = item.shortVersion.flatMap({ ReleaseVersion($0) }) else {
                throw DevFailure.checkFailed("The feed item of build \(published) has no numeric version.")
            }
            guard version > short else {
                throw DevFailure.checkFailed("VERSION \(version) must exceed the version \(short) in appcast.xml.")
            }
        }
    }

    /// The release keeps or raises the version and the build of `Configuration/Version.xcconfig`, which
    /// the last release commit wrote. When that version has a tag, its build was used, so the build must
    /// grow. A build of a candidate that was never published can be used again.
    static func checkProject(
        version: ReleaseVersion, build: Int, current: (version: String, build: String), currentIsTagged: Bool
    ) throws {
        guard let currentVersion = ReleaseVersion(current.version),
            let currentBuild = ReleaseVersion.build(current.build)
        else { throw DevFailure.checkFailed("Configuration/Version.xcconfig has a version that is not numeric.") }
        guard version >= currentVersion else {
            throw DevFailure.usage(
                "VERSION must not be lower than \(currentVersion) in Configuration/Version.xcconfig.")
        }
        let minimum = currentIsTagged ? currentBuild + 1 : currentBuild
        guard build >= minimum else {
            throw DevFailure.usage(
                "BUILD must be \(minimum) or greater: Configuration/Version.xcconfig has build \(currentBuild) "
                    + "of version \(currentVersion)\(currentIsTagged ? ", which is released" : "").")
        }
    }
}
