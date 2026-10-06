// The signed XPC check (formerly Scripts/Checks/check-xpc.swift). `SignedXPCCheckTests` signs a copy
// of this executable as `dev.jerd.app` and runs it when JERD_XPC_IDENTITY is set. It registers no
// service and changes no system file.
//
// Modes: `allow` (default) transfers two loopback listeners and checks that they keep their ports after
// the sender closes its copies. `reject-client` makes the listener require the helper identity, and
// `reject-server` makes the client require it; both must fail with an NSCocoaErrorDomain error.
import Foundation
import JerdFoundation
import JerdSystem

let mode = CommandLine.arguments.dropFirst().first ?? "allow"
do {
    let team = try CodeSigningPolicy.currentTeamID()
    let app = try CodeSigningPolicy.requirement(identifier: HelperServiceIdentity.appIdentifier, teamID: team)
    let helper = try CodeSigningPolicy.requirement(identifier: HelperServiceIdentity.helperIdentifier, teamID: team)
    let probe = try XPCProbe(requirement: mode == "reject-client" ? helper : app)
    let result = probe.acquire(clientRequirement: mode == "reject-server" ? helper : app)
    switch (mode, result) {
    case ("allow", .success(let received)):
        let expected = try probe.pair.ports()
        probe.pair.close()
        guard try received.ports() == expected else { throw JerdError.invalid("Transferred socket ports changed") }
        print("PASS: signed XPC transferred both loopback sockets; receiver retains them after sender close.")
    case (_, .failure(let error as NSError)) where mode != "allow" && error.domain == NSCocoaErrorDomain:
        print("PASS: XPC rejected the incorrect \(mode) code identity: \(error.code).")
    case (_, .success):
        throw JerdError.invalid("XPC accepted an incorrect code identity")
    case (_, .failure(let error)):
        throw error
    }
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
    exit(1)
}
