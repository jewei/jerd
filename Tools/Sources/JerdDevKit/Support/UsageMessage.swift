import ArgumentParser

/// The one format of every usage error, from the argument parser or from a command:
///
///     error: Unknown test target "JerdNope". Use one of: …
///     Usage: dev test [<target> ...] [--integration <groups>] …
///       See './dev help test' for more information.
enum UsageMessage {
    static func text(_ message: String, command: any ParsableCommand.Type) -> String {
        let usage = DevCommand.usageString(for: command)
        let names = path(to: command).map { $0.configuration.commandName ?? "" }
        let help = (["./dev help"] + names).joined(separator: " ")
        return "error: \(message)\nUsage: \(usage)\n  See '\(help)' for more information."
    }

    /// The deepest command that the leading arguments name, for example `runtimes prepare`, or the root
    /// command when the first argument is not a command.
    static func command(for arguments: [String]) -> any ParsableCommand.Type {
        var current: any ParsableCommand.Type = DevCommand.self
        var candidates = subcommands
        for argument in arguments {
            guard let next = candidates.first(where: { $0.configuration.commandName == argument }) else { break }
            current = next
            candidates = next.configuration.subcommands
        }
        return current
    }

    /// The full name of `command` without the program, for example `runtimes prepare`; `dev` for the root.
    static func commandPath(_ command: any ParsableCommand.Type) -> String {
        let names = path(to: command).compactMap { $0.configuration.commandName }
        return names.isEmpty ? "dev" : names.joined(separator: " ")
    }

    /// The commands from the first subcommand down to `command`; empty for the root command.
    static func path(to command: any ParsableCommand.Type) -> [any ParsableCommand.Type] {
        func search(_ candidates: [any ParsableCommand.Type]) -> [any ParsableCommand.Type]? {
            for candidate in candidates {
                if candidate == command { return [candidate] }
                if let rest = search(candidate.configuration.subcommands) { return [candidate] + rest }
            }
            return nil
        }
        return search(subcommands) ?? []
    }

    static var subcommands: [any ParsableCommand.Type] {
        CommandCatalog.groups.flatMap(\.subcommands)
    }

    /// The first name after `help` that is not a command, for `./dev help nope`.
    static func unknownHelpTopic(in arguments: [String]) -> String? {
        guard arguments.first == "help" else { return nil }
        var candidates = subcommands
        for name in arguments.dropFirst() where !name.hasPrefix("-") {
            guard let command = candidates.first(where: { $0.configuration.commandName == name }) else {
                return name
            }
            candidates = command.configuration.subcommands
        }
        return nil
    }
}
