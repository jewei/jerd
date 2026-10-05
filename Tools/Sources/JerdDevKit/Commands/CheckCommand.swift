import ArgumentParser

/// `./dev check`: everything that CI runs.
struct CheckCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Run everything that CI runs: lint, tests, and the Debug and Release builds.")

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        try await Stage.runAll(Stage.check, context: options.context())
    }
}
