import ArgumentParser

/// Parses the arguments, runs one command, and maps every result to a stable exit status.
public enum DevMain {
    /// The result of parsing: a command to run, the help text to show, or a usage error.
    enum Parsed {
        case command(any AsyncParsableCommand)
        case help(String)
        /// `text` is the full usage message; `reason` is its first sentence for the `--json` summary.
        case usageError(text: String, reason: String, command: any ParsableCommand.Type)
    }

    /// Runs `./dev` with the arguments after the program name and returns the process exit status.
    /// SIGINT, SIGTERM, and SIGHUP stop every running child group and end `./dev` with 128 plus the
    /// signal number.
    public static func run(arguments: [String]) async -> Int32 {
        let output = StandardTextOutput()
        SignalForwarder.installLive(output: output)
        let status = await run(arguments: arguments, output: output)
        // The forwarder ends `./dev` itself, but the command can finish first once its child stopped.
        return ChildProcessGroups.shared.stopSignal.map { 128 + $0 } ?? status
    }

    static func run(arguments: [String], output: any TextOutput) async -> Int32 {
        switch parse(arguments) {
        case .help(let text):
            output.write(text + "\n", to: .standardOutput)
            return ExitStatus.success.rawValue
        case .usageError(let text, let reason, let command):
            output.write(text + "\n", to: .standardError)
            // The parser stops before a command runs, so `--json` must still get its one summary here.
            if requestsJSON(arguments) {
                let summary = RunReport().summary(
                    command: UsageMessage.commandPath(command), status: .usage, message: reason)
                output.write(RunReport.encoded(summary) + "\n", to: .standardOutput)
            }
            return ExitStatus.usage.rawValue
        case .command(let command):
            let status = await execute(command, output: output)
            return status.rawValue
        }
    }

    /// Help requests end with status 0. Every other parse or validation error, and a help request for
    /// an unknown command, is a usage error in the format of `UsageMessage`.
    ///
    /// The root command has no `--json` option, so for `./dev nope --json` the parser names `--json`.
    /// The arguments are then parsed again without it, and the error of that parse wins when it is one.
    static func parse(_ arguments: [String]) -> Parsed {
        let parsed = parseArguments(arguments)
        guard case .usageError = parsed, requestsJSON(arguments) else { return parsed }
        let withoutJSON = parseArguments(removingJSON(arguments))
        if case .usageError = withoutJSON { return withoutJSON }
        return parsed
    }

    private static func parseArguments(_ arguments: [String]) -> Parsed {
        if let topic = UsageMessage.unknownHelpTopic(in: arguments) {
            return usageError("Unknown command \"\(topic)\".", command: DevCommand.self)
        }
        do {
            var command = try DevCommand.parseAsRoot(arguments)
            if let asyncCommand = command as? any AsyncParsableCommand {
                return .command(asyncCommand)
            }
            // Only ArgumentParser's own `help` command is synchronous. It reports the help text as an error.
            try command.run()
            return .help(DevCommand.helpMessage())
        } catch {
            guard DevCommand.exitCode(for: error) != .success else {
                return .help(DevCommand.fullMessage(for: error))
            }
            return usageError(DevCommand.message(for: error), command: UsageMessage.command(for: arguments))
        }
    }

    private static func usageError(_ reason: String, command: any ParsableCommand.Type) -> Parsed {
        .usageError(text: UsageMessage.text(reason, command: command), reason: reason, command: command)
    }

    /// True when `--json` comes before any `--` terminator, the same place where the parser reads it.
    static func requestsJSON(_ arguments: [String]) -> Bool {
        arguments.prefix(while: { $0 != "--" }).contains("--json")
    }

    /// The arguments without each `--json` before the first `--` terminator.
    static func removingJSON(_ arguments: [String]) -> [String] {
        let options = arguments.prefix(while: { $0 != "--" })
        return options.filter { $0 != "--json" } + arguments.dropFirst(options.count)
    }

    /// Runs the command. With `--json`, it also prints one JSON summary on standard output at the end.
    static func execute(_ command: any AsyncParsableCommand, output: any TextOutput) async -> ExitStatus {
        let report = (command as? any DevSubcommand)?.options.json == true ? RunReport() : nil
        let (status, message) = await RunReport.$current.withValue(report) {
            await runReportingErrors(command, output: output)
        }
        if let message {
            let text = status == .usage ? UsageMessage.text(message, command: type(of: command)) : "error: \(message)"
            output.write(text + "\n", to: .standardError)
        }
        if let report {
            let name = UsageMessage.commandPath(type(of: command))
            let summary = report.summary(command: name, status: status, message: message)
            output.write(RunReport.encoded(summary) + "\n", to: .standardOutput)
        }
        return status
    }

    /// A command group without a subcommand, for example `./dev runtimes`, shows its help and succeeds.
    private static func runReportingErrors(
        _ command: any AsyncParsableCommand, output: any TextOutput
    ) async -> (ExitStatus, String?) {
        var command = command
        do {
            try await command.run()
            return (.success, nil)
        } catch {
            if !(error is DevFailure), DevCommand.exitCode(for: error) == .success {
                output.write(DevCommand.fullMessage(for: error) + "\n", to: .standardOutput)
                return (.success, nil)
            }
            return describe(error)
        }
    }

    static func describe(_ error: any Error) -> (ExitStatus, String) {
        switch error {
        case let failure as DevFailure:
            (failure.status, failure.message)
        case let failure as InvocationFailure:
            (.checkFailed, failure.description)
        case let failure as ValidationError:
            (.usage, failure.message)
        default:
            (.checkFailed, String(describing: error))
        }
    }
}
