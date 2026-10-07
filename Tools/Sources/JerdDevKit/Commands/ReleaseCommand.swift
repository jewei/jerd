import ArgumentParser

/// `./dev release VERSION BUILD`: builds, signs, notarizes, and publishes a signed app update from this Mac.
struct ReleaseCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Build, sign, notarize, and publish a signed app update in one run.",
        discussion: """
            Needs main at origin/main with a successful ./dev check in CI, a clean tree, notes under \
            ## [Unreleased] in CHANGELOG.md, the embedded runtime payloads, the Developer ID identity, the \
            notarytool profile, and the Sparkle key (Keychain account dev.jerd.sparkle). All local work \
            comes first and writes .build/releases/Jerd-VERSION-BUILD. Then it commits "Release vVERSION" \
            with the version, the changelog, and the signed feed, pushes the tag, creates the GitHub \
            release, and pushes main last. A failure prints what is public and the recovery commands. \
            With --prepare-only it stops after the local work: no tracked file changes, any branch is \
            allowed, and nothing goes to GitHub.
            """)

    @Argument(help: ArgumentHelp("The marketing version, for example 0.2.0.", valueName: "version"))
    var version: String

    @Argument(help: ArgumentHelp("The build number, greater than every build in appcast.xml.", valueName: "build"))
    var build: String

    @Option(help: ArgumentHelp("The oldest supported macOS. Default: the deployment target.", valueName: "version"))
    var minimumMacos: String?

    @Option(
        help: ArgumentHelp(
            "The Developer ID Application identity or its SHA-1. Default: the only one of the team.",
            valueName: "identity"))
    var identity: String?

    @Option(help: ArgumentHelp("The Apple team ID of the identity.", valueName: "team"))
    var team = ReleaseNames.team

    @Option(help: ArgumentHelp("The notarytool Keychain profile.", valueName: "profile"))
    var notaryProfile = ReleaseNames.notaryProfile

    @Option(help: ArgumentHelp("The Keychain of the notarytool profile, as an absolute path.", valueName: "path"))
    var keychain: String?

    @Flag(help: "Build and check a candidate only. Change no tracked file and publish nothing.")
    var prepareOnly = false

    @OptionGroup var options: GlobalOptions

    var request: ReleaseRequest {
        ReleaseRequest(
            version: version, build: build, minimumMacOS: minimumMacos, identity: identity, team: team,
            notaryProfile: notaryProfile, keychain: keychain, prepareOnly: prepareOnly)
    }

    func validate() throws {
        do {
            try ReleaseInputs.checkForm(request)
        } catch let failure as DevFailure {
            throw ValidationError(failure.message)
        }
    }

    func run() async throws {
        let environment = try ReleaseEnvironment.live(try options.context())
        try await Releaser(environment: environment, request: request).run()
    }
}
