/// The names that every publication step uses, derived once from `release.json`.
struct PublicationFacts: Equatable, Sendable {
    let manifest: ReleaseManifest
    let version: ReleaseVersion
    let tag: String
    let branch: String
    let repository: String

    init(manifest: ReleaseManifest) throws {
        self.manifest = manifest
        version = try manifest.releaseVersion
        tag = ReleaseNames.tag(version)
        branch = ReleaseNames.feedBranch(version)
        repository = manifest.repository
    }

    var title: String { ReleaseNames.releaseTitle(version) }
    var feedCommitMessage: String { "Publish the Jerd \(version) update feed" }
}
