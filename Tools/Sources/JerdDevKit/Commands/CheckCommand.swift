import ArgumentParser

/// `./dev check`: everything that CI runs.
struct CheckCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Run everything that CI runs: lint, tests, and the Debug and Release builds.",
        // The subcommand is optional: without one, `check` runs the CI checks.
        usage: "dev check [<subcommand>] [--verbose] [--json]",
        discussion: """
            Without a subcommand, runs the CI checks. The subcommands are manual harnesses that need a \
            code-signing identity. Each writes a dated JSON evidence record in .build/evidence.
            """,
        subcommands: [CheckUpdatesCommand.self, CheckXPCCommand.self])

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        try await Stage.runAll(Stage.check, context: options.context())
    }
}
