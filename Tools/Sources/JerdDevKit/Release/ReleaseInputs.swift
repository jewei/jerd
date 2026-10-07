import JerdManifest

/// The checked inputs of `./dev release`. The minimum macOS comes from the deployment target unless
/// the user names a later one, and the signing identity is one exact certificate (its SHA-1).
struct ReleaseInputs: Equatable, Sendable {
    var version: ReleaseVersion
    var build: Int
    /// The oldest macOS that the release supports.
    var minimumMacOS: ReleaseVersion
    var signing: SigningIdentity
    var notary: NotaryCredentials
    var prepareOnly: Bool

    /// Checks the form of every option, without the Keychain. The command runs it before anything else.
    /// - Throws: `DevFailure.usage` for a value with the wrong form.
    static func checkForm(_ request: ReleaseRequest) throws {
        guard ReleaseVersion.release(request.version) != nil else {
            throw DevFailure.usage("Use a numeric VERSION with two to four parts, for example 0.2.0.")
        }
        guard ReleaseVersion.build(request.build) != nil else {
            throw DevFailure.usage("Use a positive integer BUILD, for example 3.")
        }
        if let minimum = request.minimumMacOS, ReleaseVersion(minimum, parts: 1...3) == nil {
            throw DevFailure.usage("Use a numeric macOS version for --minimum-macos, for example 14.0.")
        }
        guard PayloadReceipt.isTeamID(request.team) else {
            throw DevFailure.usage("Use a 10-character Apple team ID (A-Z, 0-9) with --team.")
        }
        if let identity = request.identity, identity.isEmpty || identity.contains("\n") {
            throw DevFailure.usage("Name the Developer ID Application identity or its SHA-1 with --identity.")
        }
        _ = try NotaryCredentials(profile: request.notaryProfile, keychain: request.keychain)
    }

    /// - Parameters:
    ///   - deploymentTarget: `MACOSX_DEPLOYMENT_TARGET` of the code. The release may not claim an older macOS.
    ///   - identities: the output of `security find-identity -v -p codesigning`.
    static func parse(
        _ request: ReleaseRequest, deploymentTarget: ReleaseVersion, identities: String
    ) throws -> ReleaseInputs {
        try checkForm(request)
        guard let version = ReleaseVersion.release(request.version), let build = ReleaseVersion.build(request.build)
        else { preconditionFailure("checked above") }
        let minimum = request.minimumMacOS.flatMap { ReleaseVersion($0, parts: 1...3) } ?? deploymentTarget
        guard minimum >= deploymentTarget else {
            throw DevFailure.usage(
                "--minimum-macos must be \(deploymentTarget) or later, the deployment target of the code.")
        }
        return ReleaseInputs(
            version: version, build: build, minimumMacOS: minimum,
            signing: try SigningIdentity.select(request.identity, team: request.team, identities: identities),
            notary: try NotaryCredentials(profile: request.notaryProfile, keychain: request.keychain),
            prepareOnly: request.prepareOnly)
    }

    var tag: String { ReleaseNames.tag(version) }
    var diskImageName: String { ReleaseNames.diskImage(version) }
    var symbolsName: String { ReleaseNames.symbols(version, build: build) }
}
