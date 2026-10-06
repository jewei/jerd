import Darwin
import Foundation

/// What the shell gave the launcher: the argument vector, the environment, and the working folder.
public struct CLIInvocation: Equatable, Sendable {
    /// The complete argument vector. `arguments[0]` is the link name, for example `php`.
    public let arguments: [String]
    public let environment: [String: String]
    /// The working folder, or nil when it cannot be read (for example, it was deleted).
    public let workingDirectory: String?

    public init(arguments: [String], environment: [String: String], workingDirectory: String?) {
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    /// The invocation of the current process.
    public static func current() -> CLIInvocation {
        CLIInvocation(
            arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment,
            workingDirectory: currentDirectory())
    }

    private static func currentDirectory() -> String? {
        guard let pointer = getcwd(nil, 0) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
