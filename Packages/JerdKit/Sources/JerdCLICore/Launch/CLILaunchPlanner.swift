import JerdFoundation

/// Builds the exact command line and environment of one command. Pure.
///
/// Command lines:
/// - `php [args]` → `<php> [-c <ini>] [args]`
/// - `composer [args]` → `<php> [-c <ini>] <composer.phar> [args]`
/// - `laravel [args]` → `<php> [-c <ini>] <laravel installer> [args]`
///
/// `PATH` starts with Jerd's `bin` folder exactly once, so commands that PHP starts select their
/// runtime the same way, and nested calls do not grow `PATH`.
public enum CLILaunchPlanner {
    /// The search path when the environment has no `PATH` or an empty one.
    public static let fallbackSearchPath = "/usr/bin:/bin"

    /// - Throws: `.invalid` for a relative PHP path or a companion script that does not fit the command.
    public static func plan(_ request: CLILaunchRequest) throws -> CLILaunchPlan {
        guard request.phpExecutable.hasPrefix("/") else {
            throw JerdError.invalid("The PHP runtime path must be absolute: \(request.phpExecutable)")
        }
        guard request.command.runsCompanionScript == (request.companionScript != nil) else {
            throw JerdError.invalid("The \(request.command.rawValue) command has no matching tool script.")
        }
        let arguments =
            [request.phpExecutable] + request.iniArguments + (request.companionScript.map { [$0] } ?? [])
            + request.userArguments
        var changes = request.iniEnvironment
        changes["PATH"] = searchPath(prepending: request.binDirectory, to: request.environment["PATH"])
        return CLILaunchPlan(executable: request.phpExecutable, arguments: arguments, environmentChanges: changes)
    }

    /// `directory` first, then every other entry of `path` in its order. Idempotent.
    ///
    /// Empty entries of a non-empty `path` stay: they are the user's choice. A missing or empty
    /// `path` becomes the system default, never the current folder.
    public static func searchPath(prepending directory: String, to path: String?) -> String {
        guard let path, !path.isEmpty else { return "\(directory):\(fallbackSearchPath)" }
        let others = path.split(separator: ":", omittingEmptySubsequences: false).filter { $0 != directory }
        return ([directory] + others.map(String.init)).joined(separator: ":")
    }
}
