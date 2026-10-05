import ArgumentParser

/// Parses the arguments, runs one command, and maps every result to a stable exit status.
public enum DevMain {
    /// The result of parsing: a command to run, or an exit status with the text to show.
    enum Parsed {
        case command(any AsyncParsableCommand)
        case exit(ExitStatus, message: String)
    }

    /// Runs `./dev` with the arguments after the program name and returns the process exit status.
    /// SIGINT, SIGTERM, and SIGHUP stop every running child group and end `./dev` with 128 plus the
    /// signal number.
    public static func run(arguments: [String]) async -> Int32 {
        let output = StandardTextOutput()
        SignalForwarder.installLive(output: output)
        return await run(arguments: arguments, output: output)
    }

    static func run(arguments: [String], output: any TextOutput) async -> Int32 {
        switch parse(arguments) {
        case .exit(let status, let message):
            output.write(message + "\n", to: status == .success ? .standardOutput : .standardError)
            return status.rawValue
        case .command(let command):
            let status = await execute(command, output: output)
            return status.rawValue
        }
    }

    /// Help requests end with status 0. Every other parse or validation error, and a help request for
    /// an unknown command, is a usage error in the format of `UsageMessage`.
    static func parse(_ arguments: [String]) -> Parsed {
        if let topic = UsageMessage.unknownHelpTopic(in: arguments) {
            return .exit(.usage, message: UsageMessage.text("Unknown command \"\(topic)\".", command: DevCommand.self))
        }
        do {
            var command = try DevCommand.parseAsRoot(arguments)
            if let asyncCommand = command as? any AsyncParsableCommand {
                return .command(asyncCommand)
            }
            // Only ArgumentParser's own `help` command is synchronous. It reports the help text as an error.
            try command.run()
            return .exit(.success, message: DevCommand.helpMessage())
        } catch {
            guard DevCommand.exitCode(for: error) != .success else {
                return .exit(.success, message: DevCommand.fullMessage(for: error))
            }
            let command = UsageMessage.command(named: arguments.first)
            return .exit(.usage, message: UsageMessage.text(DevCommand.message(for: error), command: command))
        }
    }

    /// Runs the command. With `--json`, it also prints one JSON summary on standard output at the end.
    static func execute(_ command: any AsyncParsableCommand, output: any TextOutput) async -> ExitStatus {
        let report = (command as? any DevSubcommand)?.options.json == true ? RunReport() : nil
        let (status, message) = await RunReport.$current.withValue(report) { await runReportingErrors(command) }
        if let message {
            let text = status == .usage ? UsageMessage.text(message, command: type(of: command)) : "error: \(message)"
            output.write(text + "\n", to: .standardError)
        }
        if let report {
            let name = type(of: command).configuration.commandName ?? "dev"
            let summary = report.summary(command: name, status: status, message: message)
            output.write(RunReport.encoded(summary) + "\n", to: .standardOutput)
        }
        return status
    }

    private static func runReportingErrors(_ command: any AsyncParsableCommand) async -> (ExitStatus, String?) {
        var command = command
        do {
            try await command.run()
            return (.success, nil)
        } catch {
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
