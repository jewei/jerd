/// What `./dev build` builds: a configuration and an optional signing identity.
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
    var verbose = false

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
