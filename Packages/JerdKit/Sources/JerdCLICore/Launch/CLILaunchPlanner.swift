import JerdFoundation

/// Builds the exact command line and environment of one command. Pure over the path canonicalizer.
///
/// Command lines:
/// - `php [args]` → `<php> [-c <ini>] [args]`
/// - `composer [args]` → `<php> [-c <ini>] <composer.phar> [args]`
/// - `laravel [args]` → `<php> [-c <ini>] <laravel installer> [args]`
///
/// The user arguments and `PATH` stay raw bytes. `PATH` starts with Jerd's `bin` folder exactly
/// once, so commands that PHP starts select their runtime the same way, and nested calls do not
/// grow `PATH`.
enum CLILaunchPlanner {
    /// - Throws: `.invalid` for a relative PHP path or a companion script that does not fit the command.
    static func plan(
        _ request: CLILaunchRequest, canonicalize: @escaping SearchPath.Canonicalizer = SearchPath.canonical
    ) throws -> CLILaunchPlan {
        guard request.phpExecutable.hasPrefix("/") else {
            throw JerdError.invalid("The PHP runtime path must be absolute: \(request.phpExecutable)")
        }
        guard request.command.runsCompanionScript == (request.companionScript != nil) else {
            throw JerdError.invalid("The \(request.command.rawValue) command has no matching tool script.")
        }
        let launcherPart = [request.phpExecutable] + request.iniArguments + (request.companionScript.map { [$0] } ?? [])
        var changes = request.iniEnvironment.mapValues { Array($0.utf8) }
        changes[SearchPath.variable] = SearchPath.prepending(
            Array(request.binDirectory.utf8), to: request.environment.value(SearchPath.variable),
            canonicalize: canonicalize)
        return CLILaunchPlan(
            executable: request.phpExecutable, arguments: launcherPart.map { Array($0.utf8) } + request.userArguments,
            environment: request.environment.setting(changes))
    }
}
