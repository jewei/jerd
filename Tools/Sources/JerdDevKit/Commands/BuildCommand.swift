import ArgumentParser

/// `./dev build`: builds the app with one `xcodebuild` call.
struct BuildCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the app: unsigned Debug unless options say otherwise.",
        discussion: """
            Every build then checks the built app: the update feed URL and public key in Info.plist, \
            the Sparkle keys, and arm64-only executables. A Release build requires the prepared runtime \
            payloads. --allow-missing-runtimes turns this off for an unsigned check build; ./dev check \
            and CI use it because they have no runtimes. Never ship such a build.
            """)

    @Flag(help: "Build the Release configuration.")
    var release = false

    @Option(help: ArgumentHelp("Sign with this code-signing identity. Requires --team.", valueName: "identity"))
    var sign: String?

    @Option(help: ArgumentHelp("The development team of the signing identity. Requires --sign.", valueName: "team"))
    var team: String?

    @Flag(help: "Build Release without the runtime payloads, unsigned, for checks only. ./dev check uses it.")
    var allowMissingRuntimes = false

    @OptionGroup var options: GlobalOptions

    func validate() throws {
        do {
            let signing = try BuildOptions.signing(identity: sign, team: team)
            try BuildOptions.validateMissingRuntimes(
                allowed: allowMissingRuntimes, configuration: release ? .release : .debug, signing: signing)
        } catch let failure as DevFailure {
            throw ValidationError(failure.message)
        }
    }

    func run() async throws {
        let context = try options.context()
        let buildOptions = BuildOptions(
            configuration: release ? .release : .debug,
            signing: try BuildOptions.signing(identity: sign, team: team),
            allowsMissingRuntimes: allowMissingRuntimes,
            verbose: options.verbose)
        try await StepSequence.runSingle("\(buildOptions.configuration.rawValue) build", console: context.console) {
            try await BuildStep.run(context, options: buildOptions)
        }
    }
}
