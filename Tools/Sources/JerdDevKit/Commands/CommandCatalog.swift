import ArgumentParser

/// Every `./dev` command, grouped by purpose for the help list. A new command is one file in
/// `Commands/` plus one entry here.
enum CommandCatalog {
    static let groups: [CommandGroup] = [
        CommandGroup(
            name: "Everyday",
            subcommands: [CheckCommand.self, TestCommand.self, BuildCommand.self, SnapshotsCommand.self]),
        CommandGroup(
            name: "Code quality",
            subcommands: [FormatCommand.self, LintCommand.self, GenerateCommand.self]),
        CommandGroup(
            name: "Setup and maintenance",
            subcommands: [DoctorCommand.self, CleanCommand.self]),
        CommandGroup(name: "Runtimes", subcommands: [RuntimesCommand.self]),
        CommandGroup(name: "Release", subcommands: [ReleaseCommand.self]),
    ]
}
