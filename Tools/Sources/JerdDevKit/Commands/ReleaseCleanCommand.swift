import ArgumentParser

/// `./dev release clean`: removes old release candidates.
struct ReleaseCleanCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Remove old candidates in .build/releases and keep the newest ones.",
        discussion: """
            A candidate whose publication started and is not finished, and a candidate that is being \
            prepared, always stay.
            """)

    @Option(help: ArgumentHelp("How many of the newest candidates to keep.", valueName: "count"))
    var keep = 3

    @OptionGroup var options: GlobalOptions

    func validate() throws {
        guard keep >= 0 else { throw ValidationError("--keep must be 0 or more.") }
    }

    func run() async throws {
        let environment = try ReleaseEnvironment.live(try options.context())
        try await StepSequence.runSingle("Release clean", console: environment.console) {
            try CandidateCleaner(environment: environment).run(keep: keep)
        }
    }
}
