import ArgumentParser

/// The one format of every usage error, from the argument parser or from a command:
///
///     error: Unknown test target "JerdNope". Use one of: …
///     Usage: dev test [<target> ...] [--integration <groups>] …
///       See './dev help test' for more information.
enum UsageMessage {
    static func text(_ message: String, command: any ParsableCommand.Type) -> String {
        let usage = DevCommand.usageString(for: command)
        let name = command.configuration.commandName ?? ""
        let help = command == DevCommand.self ? "./dev help" : "./dev help \(name)"
        return "error: \(message)\nUsage: \(usage)\n  See '\(help)' for more information."
    }

    /// The subcommand with this name, or the root command when no subcommand has it.
    static func command(named name: String?) -> any ParsableCommand.Type {
        subcommands.first { $0.configuration.commandName == name } ?? DevCommand.self
    }

    static var subcommands: [any ParsableCommand.Type] {
        CommandCatalog.groups.flatMap(\.subcommands)
    }

    /// The first name after `help` that is not a command, for `./dev help nope`.
    static func unknownHelpTopic(in arguments: [String]) -> String? {
        guard arguments.first == "help" else { return nil }
        let names = Set(subcommands.compactMap { $0.configuration.commandName })
        return arguments.dropFirst().first { !$0.hasPrefix("-") && !names.contains($0) }
    }
}
