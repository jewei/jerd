import JerdManifest

/// The checked inputs of `./dev release prepare`. Every value is explicit: the minimum macOS version,
/// the signing identity, the team, and the notary profile never come from the build Mac or from code.
struct ReleaseInputs: Equatable, Sendable {
    var version: ReleaseVersion
    var build: Int
    /// The oldest macOS that the release supports. Release testing must cover it.
    var minimumMacOS: ReleaseVersion
    var signing: SigningIdentity
    var notary: NotaryCredentials

    /// - Throws: `DevFailure.usage` for a value with the wrong form.
    static func parse(
        version: String, build: String, minimumMacOS: String, identity: String, team: String,
        notaryProfile: String, keychain: String?
    ) throws -> ReleaseInputs {
        guard let releaseVersion = ReleaseVersion.release(version) else {
            throw DevFailure.usage("Use a numeric version with two to four parts, for example 0.2.0.")
        }
        guard let buildNumber = ReleaseVersion.build(build) else {
            throw DevFailure.usage("Use a positive integer build number, for example 3.")
        }
        guard let minimum = ReleaseVersion(minimumMacOS, parts: 1...3) else {
            throw DevFailure.usage("Use a numeric macOS version for --minimum-macos, for example 14.0.")
        }
        return ReleaseInputs(
            version: releaseVersion, build: buildNumber, minimumMacOS: minimum,
            signing: try SigningIdentity(identity: identity, team: team),
            notary: try NotaryCredentials(profile: notaryProfile, keychain: keychain))
    }
}
