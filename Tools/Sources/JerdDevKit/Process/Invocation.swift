import Foundation

/// One planned external command: an absolute executable and an argument array, never a shell line.
public struct Invocation: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    /// The complete child environment, or `nil` to inherit the environment of `./dev`.
    public var environment: [String: String]?
    public var workingDirectory: URL?
    public var timeout: Duration

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        timeout: Duration
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }

    /// The command as a user can paste it into a terminal. Only for display; the runner never uses a shell.
    public var commandLine: String {
        ([executable.path] + arguments).map(Self.quotedForDisplay).joined(separator: " ")
    }

    static func quotedForDisplay(_ word: String) -> String {
        let plain = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./=:,@%+")
        if !word.isEmpty, word.unicodeScalars.allSatisfy(plain.contains) {
            return word
        }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
