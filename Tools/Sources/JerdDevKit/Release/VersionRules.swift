import JerdManifest

/// The version rules of a release. Sparkle offers an update only for a higher build, and users compare
/// marketing versions, so both must grow with every release.
enum VersionRules {
    /// The new build and version exceed every item of the published feed. An empty feed is valid.
    static func checkFeed(version: ReleaseVersion, build: Int, items: [AppcastItem]) throws {
        for item in items {
            guard let published = ReleaseVersion.build(item.bundleVersion) else {
                throw DevFailure.checkFailed("The feed has an item with the build \(item.bundleVersion).")
            }
            guard build > published else {
                throw DevFailure.checkFailed("The build \(build) must exceed the published build \(published).")
            }
            guard let short = item.shortVersion.flatMap({ ReleaseVersion($0) }) else {
                throw DevFailure.checkFailed("The feed item of build \(published) has no numeric version.")
            }
            guard version > short else {
                throw DevFailure.checkFailed("The version \(version) must exceed the published version \(short).")
            }
        }
    }

    /// A bump raises the build and keeps or raises the version of `Configuration/Version.xcconfig`.
    static func checkBump(
        version: ReleaseVersion, build: Int, current: (version: String, build: String), items: [AppcastItem]
    ) throws {
        guard let currentVersion = ReleaseVersion(current.version),
            let currentBuild = ReleaseVersion.build(current.build)
        else { throw DevFailure.checkFailed("Configuration/Version.xcconfig has a version that is not numeric.") }
        guard build > currentBuild else {
            throw DevFailure.usage("The build must exceed the current build \(currentBuild).")
        }
        guard version >= currentVersion else {
            throw DevFailure.usage("The version must not be lower than the current version \(currentVersion).")
        }
        try checkFeed(version: version, build: build, items: items)
    }

    /// Preparation builds exactly the version that the reviewed source commit sets.
    static func checkSource(version: ReleaseVersion, build: Int, file: (version: String, build: String)) throws {
        guard file.version == version.text, file.build == String(build) else {
            throw DevFailure.checkFailed(
                "Configuration/Version.xcconfig sets \(file.version) (\(file.build)), not \(version) (\(build)). "
                    + "Run ./dev release bump, merge the change, and prepare again.")
        }
    }
}
