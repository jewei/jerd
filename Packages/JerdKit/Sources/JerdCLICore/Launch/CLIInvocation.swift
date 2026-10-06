import Darwin

/// What the shell gave the launcher: the exact argument and environment bytes, and the working folder.
///
/// The bytes stay as the kernel gave them, so PHP gets the same bytes, also bytes that are not
/// UTF-8. Decisions (the command name, the INI options) use decoded copies.
public struct CLIInvocation: Equatable, Sendable {
    /// The argument vector bytes. `arguments[0]` is the link name, for example `php`.
    package let arguments: [[UInt8]]
    package let environment: CLIEnvironment
    /// The working folder, or nil when it cannot be read (for example, it was deleted).
    package let workingDirectory: String?

    package init(arguments: [[UInt8]], environment: CLIEnvironment, workingDirectory: String?) {
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    /// The invocation of the current process, from `argv` and `environ` without a text decoding.
    public static func current() -> CLIInvocation {
        CLIInvocation(
            arguments: CStrings.list(UnsafePointer(CommandLine.unsafeArgv)),
            environment: CLIEnvironment(entries: CStrings.list(UnsafePointer(environ))),
            workingDirectory: currentDirectory())
    }

    /// The decoded argument vector, for the decisions only. Never passed to PHP.
    package var decodedArguments: [String] { arguments.map { String(decoding: $0, as: UTF8.self) } }

    private static func currentDirectory() -> String? {
        guard let pointer = getcwd(nil, 0) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
