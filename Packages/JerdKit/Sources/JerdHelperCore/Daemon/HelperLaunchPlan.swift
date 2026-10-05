import Darwin
import JerdFoundation
import JerdSystem

/// What the helper process does at start, decided before any listener exists.
///
/// The team ID comes first, because both modes need it. `--check-signing` (the only argument)
/// prints the team and needs no root. Otherwise the process must run as root, which launchd does
/// for the approved `SMAppService` daemon.
enum HelperLaunchPlan: Equatable {
    case printSigning(message: String)
    case listen(requirement: String)

    static func decide(
        arguments: [String], effectiveUserID: uid_t, teamID: () throws -> String
    ) throws
        -> HelperLaunchPlan
    {
        let team = try teamID()
        let requirement = try CodeSigningPolicy.requirement(
            identifier: HelperServiceIdentity.appIdentifier, teamID: team)
        if arguments.dropFirst() == ["--check-signing"] {
            return .printSigning(message: "Jerd helper requires the signed app from team \(team).")
        }
        guard effectiveUserID == 0 else {
            throw JerdError.unavailable("Launch this helper through Jerd's approved SMAppService setup.")
        }
        return .listen(requirement: requirement)
    }
}
