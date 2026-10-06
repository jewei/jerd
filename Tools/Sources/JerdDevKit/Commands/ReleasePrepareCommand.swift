import ArgumentParser

/// `./dev release prepare`: builds a private, signed, notarized candidate.
struct ReleasePrepareCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "prepare",
        abstract: "Build, sign, test, notarize, and validate a private release candidate.",
        discussion: """
            Needs a clean worktree whose Configuration/Version.xcconfig sets --version and --build, a \
            CHANGELOG.md section of the version, every prepared runtime payload, the Sparkle key in the \
            Keychain account dev.jerd.sparkle, and the notarytool profile. The candidate goes to \
            .build/releases. Nothing becomes public.
            """)

    @Option(help: ArgumentHelp("The version that Configuration/Version.xcconfig sets.", valueName: "version"))
    var version: String

    @Option(help: ArgumentHelp("The build that Configuration/Version.xcconfig sets.", valueName: "build"))
    var build: String

    @Option(help: ArgumentHelp("The oldest macOS that release testing covers, for example 14.0.", valueName: "version"))
    var minimumMacos: String

    @Option(help: ArgumentHelp("The Developer ID Application identity in the Keychain.", valueName: "identity"))
    var identity: String

    @Option(help: ArgumentHelp("The Apple team ID of the identity.", valueName: "team"))
    var team: String

    @Option(help: ArgumentHelp("The notarytool Keychain profile.", valueName: "profile"))
    var notaryProfile = "notarytool"

    @Option(help: ArgumentHelp("The Keychain of the notarytool profile, as an absolute path.", valueName: "path"))
    var keychain: String?

    @OptionGroup var options: GlobalOptions

    func inputs() throws -> ReleaseInputs {
        try ReleaseInputs.parse(
            version: version, build: build, minimumMacOS: minimumMacos, identity: identity, team: team,
            notaryProfile: notaryProfile, keychain: keychain)
    }

    func validate() throws {
        do {
            _ = try inputs()
        } catch let failure as DevFailure {
            throw ValidationError(failure.message)
        }
    }

    func run() async throws {
        let environment = try ReleaseEnvironment.live(try options.context())
        let inputs = try inputs()
        try await StepSequence.runSingle("Release candidate", console: environment.console) {
            try await ReleasePreparer(environment: environment, inputs: inputs).run()
        }
    }
}
