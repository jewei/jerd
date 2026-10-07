import Foundation

/// Checks one signed file of a release: the Developer ID requirement of the team, the hardened runtime,
/// a secure timestamp, the identifier, and no debug entitlement. Strict recursive verification alone
/// also accepts valid ad hoc signatures, so every nested file is checked on its own.
struct SignatureVerifier: Sendable {
    /// The identifier that a signature must have.
    enum IdentifierRule: Equatable, Sendable {
        case exact(String)
        case prefix(String)
        case any

        func accepts(_ identifier: String?) -> Bool {
            switch self {
            case .exact(let value): identifier == value
            case .prefix(let value): identifier?.hasPrefix(value) == true && identifier != value
            case .any: identifier?.isEmpty == false
            }
        }
    }

    let shell: ReleaseShell
    let team: String

    func verify(_ file: URL, identifier rule: IdentifierRule) async throws {
        let name = file.lastPathComponent
        try await shell.run(
            SystemProgram.codesign, ["--verify", "--strict", "-R", SigningIdentity.requirement(team: team), file.path],
            limit: TimeLimit.codeSigning)
        let display = try await shell.run(
            SystemProgram.codesign, ["-d", "--verbose=4", file.path], limit: TimeLimit.codeSigning)
        let details = CodeSignatureDetails.parse(display.standardError)
        guard details.hasHardenedRuntime, details.hasTimestamp else {
            throw DevFailure.checkFailed("\(name) has no hardened runtime or no secure timestamp.")
        }
        guard details.teamIdentifier == team else {
            throw DevFailure.checkFailed("\(name) is signed by another team.")
        }
        guard rule.accepts(details.identifier) else {
            throw DevFailure.checkFailed("\(name) has the signing identifier \(details.identifier ?? "none").")
        }
        let entitlements = try await shell.run(
            SystemProgram.codesign, ["-d", "--entitlements", "-", "--xml", file.path], limit: TimeLimit.codeSigning)
        guard try !EntitlementPolicy.grantsDebugging(Data(entitlements.standardOutput.utf8), file: name) else {
            throw DevFailure.checkFailed("\(name) has the debug entitlement get-task-allow.")
        }
    }
}
