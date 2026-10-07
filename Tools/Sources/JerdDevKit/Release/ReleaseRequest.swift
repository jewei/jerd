/// The options of `./dev release` as the user typed them. `ReleaseInputs.parse` checks them.
struct ReleaseRequest: Equatable, Sendable {
    var version: String
    var build: String
    /// Nil: the deployment target in `Configuration/Base.xcconfig`.
    var minimumMacOS: String?
    /// Nil: the only Developer ID Application identity of the team. A name or a SHA-1 selects one.
    var identity: String?
    var team = ReleaseNames.team
    var notaryProfile = ReleaseNames.notaryProfile
    var keychain: String?
    /// Build and check a candidate only: no tracked file changes, and nothing goes to GitHub.
    var prepareOnly = false
}
