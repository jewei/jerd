import ArgumentParser

/// Parses the arguments, runs one command, and maps every result to a stable exit status.
public enum DevMain {
    /// The result of parsing: a command to run, or an exit status with the text to show.
    enum Parsed {
        case command(any AsyncParsableCommand)
        case exit(ExitStatus, message: String)
    }

    public static func run(arguments: [String], output: any TextOutput = StandardTextOutput()) async -> Int32 {
        switch parse(arguments) {
        case .exit(let status, let message):
            output.write(message + "\n", to: status == .success ? .standardOutput : .standardError)
            return status.rawValue
        case .command(let command):
            let status = await execute(command, output: output)
            return status.rawValue
        }
    }

    /// Help requests end with status 0. Every other parse or validation error is a usage error.
    static func parse(_ arguments: [String]) -> Parsed {
        do {
            var command = try DevCommand.parseAsRoot(arguments)
            if let asyncCommand = command as? any AsyncParsableCommand {
                return .command(asyncCommand)
            }
            // Only ArgumentParser's own `help` command is synchronous. It reports the help text as an error.
            try command.run()
            return .exit(.success, message: DevCommand.helpMessage())
        } catch {
            let message = DevCommand.fullMessage(for: error)
            let status: ExitStatus = DevCommand.exitCode(for: error) == .success ? .success : .usage
            return .exit(status, message: message)
        }
    }

    static func execute(_ command: any AsyncParsableCommand, output: any TextOutput) async -> ExitStatus {
        var command = command
        do {
            try await command.run()
            return .success
        } catch {
            let (status, message) = describe(error)
            output.write("error: \(message)\n", to: .standardError)
            return status
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
