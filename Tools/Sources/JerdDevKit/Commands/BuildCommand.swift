import ArgumentParser

/// `./dev build`: builds the app with one `xcodebuild` call.
struct BuildCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the app: unsigned Debug unless options say otherwise.")

    @Flag(help: "Build the Release configuration.")
    var release = false

    @Option(help: ArgumentHelp("Sign with this code-signing identity. Requires --team.", valueName: "identity"))
    var sign: String?

    @Option(help: ArgumentHelp("The development team of the signing identity. Requires --sign.", valueName: "team"))
    var team: String?

    @OptionGroup var options: GlobalOptions

    func validate() throws {
        do {
            _ = try BuildOptions.signing(identity: sign, team: team)
        } catch let failure as DevFailure {
            throw ValidationError(failure.message)
        }
    }

    func run() async throws {
        let context = try options.context()
        let buildOptions = BuildOptions(
            configuration: release ? .release : .debug,
            signing: try BuildOptions.signing(identity: sign, team: team),
            verbose: options.verbose)
        try await StepSequence.runSingle("\(buildOptions.configuration.rawValue) build", console: context.console) {
            try await BuildStep.run(context, options: buildOptions)
        }
    }
}
