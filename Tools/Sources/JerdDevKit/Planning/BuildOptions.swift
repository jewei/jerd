/// What `./dev build` builds: a configuration, an optional signing identity, and whether a Release
/// build may lack the runtime payloads.
struct BuildOptions: Equatable, Sendable {
    enum Configuration: String, Sendable {
        case debug = "Debug"
        case release = "Release"
    }

    /// A code-signing identity and its team. Without one, the build is unsigned.
    struct Signing: Equatable, Sendable {
        var identity: String
        var team: String
    }

    var configuration: Configuration = .debug
    var signing: Signing?
    /// Turns off the Release gate `JERD_REQUIRE_RUNTIMES` for an unsigned check build. Only
    /// `./dev check` (and so CI) uses it: CI has no prepared runtimes, but must compile Release.
    var allowsMissingRuntimes = false
    var verbose = false

    /// `--allow-missing-runtimes` is only for an unsigned Release build. A signed build is for release,
    /// and a Debug build never requires runtimes.
    static func validateMissingRuntimes(allowed: Bool, configuration: Configuration, signing: Signing?) throws {
        guard allowed else { return }
        guard configuration == .release else {
            throw DevFailure.usage("Use --allow-missing-runtimes only with --release.")
        }
        guard signing == nil else {
            throw DevFailure.usage("A signed build must contain the runtimes. Remove --allow-missing-runtimes.")
        }
    }

    /// Accepts both `--sign` and `--team`, or neither.
    static func signing(identity: String?, team: String?) throws -> Signing? {
        switch (identity, team) {
        case (nil, nil):
            return nil
        case (let identity?, let team?) where !identity.isEmpty && !team.isEmpty:
            return Signing(identity: identity, team: team)
        default:
            throw DevFailure.usage("Use --sign IDENTITY and --team TEAM together.")
        }
    }
}
