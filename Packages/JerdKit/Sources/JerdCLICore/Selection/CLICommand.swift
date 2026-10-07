import JerdFoundation

/// The three commands that the launcher serves. The link name that runs the launcher selects one.
package enum CLICommand: String, CaseIterable, Sendable {
    case php
    case composer
    case laravel

    /// The command of `argv[0]`: the last path component of the link that the shell ran.
    /// - Throws: `.invalid` when the launcher runs under another name.
    package init(invocationName: String) throws {
        let name = invocationName.split(separator: "/").last.map(String.init) ?? ""
        guard let command = CLICommand(rawValue: name) else {
            throw JerdError.invalid(
                "Run Jerd's launcher as php, composer, or laravel. To install these commands, open Jerd, "
                    + "go to Advanced, and choose Install Command-Line Tools.")
        }
        self = command
    }

    /// True for `composer` and `laravel`: PHP runs their script before the user arguments.
    package var runsCompanionScript: Bool { self != .php }
}
