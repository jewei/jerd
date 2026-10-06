import JerdManifest

/// A Developer ID Application identity in the Keychain and its Apple team.
struct SigningIdentity: Equatable, Sendable {
    let identity: String
    let team: String

    init(identity: String, team: String) throws {
        guard !identity.isEmpty, !identity.contains("\n") else {
            throw DevFailure.usage("Name the Developer ID Application identity with --identity.")
        }
        guard PayloadReceipt.isTeamID(team) else {
            throw DevFailure.usage("Use a 10-character Apple team ID (A-Z, 0-9) with --team.")
        }
        self.identity = identity
        self.team = team
    }

    /// The Developer ID requirement of every signed file of `team`. A leading `=` makes codesign read it
    /// inline; the OID marks a Developer ID Application certificate.
    static func requirement(team: String) -> String {
        "=anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    }
}
