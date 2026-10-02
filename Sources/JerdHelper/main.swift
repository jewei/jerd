import Foundation
import JerdCore
import Darwin

do {
    let team = try SystemService.currentTeamID()
    let requirement = try SystemService.signingRequirement(identifier: SystemService.appIdentifier, teamID: team)
    if CommandLine.arguments == [CommandLine.arguments[0], "--check-signing"] {
        print("Jerd helper requires the signed app from team \(team).")
        exit(0)
    }
    guard geteuid() == 0 else { throw JerdError.unavailable("Launch this helper through Jerd's approved SMAppService setup.") }
    let listener = NSXPCListener(machServiceName: SystemService.name)
    let delegate = HelperListener(requirement: requirement)
    listener.setConnectionCodeSigningRequirement(requirement)
    listener.delegate = delegate
    listener.resume()
    withExtendedLifetime(delegate) { dispatchMain() }
} catch {
    FileHandle.standardError.write(Data("Jerd helper: \(error.localizedDescription)\n".utf8))
    exit(1)
}
