import JerdFoundation

/// The three commands that the launcher serves. The link name that runs the launcher selects one.
public enum CLICommand: String, CaseIterable, Sendable {
    case php
    case composer
    case laravel

    /// The command of `argv[0]`: the last path component of the link that the shell ran.
    /// - Throws: `.invalid` when the launcher runs under another name.
    public init(invocationName: String) throws {
        let name = invocationName.split(separator: "/").last.map(String.init) ?? ""
        guard let command = CLICommand(rawValue: name) else {
            throw JerdError.invalid(
                "Run Jerd's launcher as php, composer, or laravel. Set up these commands in Jerd first.")
        }
        self = command
    }

    /// True for `composer` and `laravel`: PHP runs their script before the user arguments.
    public var runsCompanionScript: Bool { self != .php }
}
