import ArgumentParser

/// The root of `./dev`. Without a subcommand it prints the grouped command list.
struct DevCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dev",
        abstract: "Build, test, and check Jerd. Run every command from any folder in the repository.",
        discussion: """
            Exit status: 0 success, 1 a check failed, 2 usage error, 3 a prerequisite is missing,
            128 plus the signal number when a signal stops ./dev.
            Add --verbose to a command to see each underlying command line.
            Add --json to a command to get one JSON summary on standard output.
            Run ./dev help COMMAND to see the options of a command.
            """,
        groupedSubcommands: CommandCatalog.groups
    )

    func run() async throws {
        Console(output: StandardTextOutput(), verbose: false).plain(Self.helpMessage())
    }
}
