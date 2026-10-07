import JerdFoundation
import JerdManifest

/// One Developer ID Application certificate in the Keychain, named by its SHA-1, and its Apple team.
/// The SHA-1 stays exact when two certificates have the same name, for example during a renewal.
struct SigningIdentity: Equatable, Sendable {
    static let namePrefix = "Developer ID Application: "

    /// The SHA-1 of the certificate. `codesign` and `xcodebuild` accept it as the identity.
    let identity: String
    let team: String
    /// The common name, for messages.
    var name = ""

    init(identity: String, team: String, name: String = "") throws {
        guard !identity.isEmpty, !identity.contains("\n") else {
            throw DevFailure.usage("Name the Developer ID Application identity with --identity.")
        }
        guard PayloadReceipt.isTeamID(team) else {
            throw DevFailure.usage("Use a 10-character Apple team ID (A-Z, 0-9) with --team.")
        }
        self.identity = identity
        self.team = team
        self.name = name
    }

    /// Selects one valid Developer ID Application identity of `team`.
    /// - Parameters:
    ///   - request: nil for the only identity of the team, a common name, or a SHA-1.
    ///   - identities: the output of `security find-identity -v -p codesigning`.
    static func select(_ request: String?, team: String, identities: String) throws -> SigningIdentity {
        let candidates = parse(identities).filter {
            $0.name.hasPrefix(namePrefix) && $0.name.hasSuffix("(\(team))")
        }
        let matches = candidates.filter { candidate in
            guard let request else { return true }
            return isSHA1(request) ? candidate.sha1 == request.uppercased() : candidate.name == request
        }
        let unique = Dictionary(matches.map { ($0.sha1, $0.name) }, uniquingKeysWith: { first, _ in first })
        guard let match = unique.first else {
            let wanted = request.map { "\"\($0)\"" } ?? "of team \(team)"
            throw DevFailure.missingPrerequisite(
                "The Keychain has no valid Developer ID Application identity \(wanted).")
        }
        guard unique.count == 1 else {
            let list = unique.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "; ")
            throw DevFailure.usage("More than one identity matches. Name one with --identity SHA-1: \(list).")
        }
        return try SigningIdentity(identity: match.key, team: team, name: match.value)
    }

    /// The lines `  1) <SHA-1> "<name>"` of `security find-identity`.
    static func parse(_ output: String) -> [(sha1: String, name: String)] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2)
            guard parts.count == 3, parts[0].hasSuffix(")"), isSHA1(String(parts[1])),
                parts[2].hasPrefix("\""), parts[2].hasSuffix("\""), parts[2].count >= 2
            else { return nil }
            return (String(parts[1]).uppercased(), String(parts[2].dropFirst().dropLast()))
        }
    }

    /// A SHA-1 in hexadecimal, in either letter case.
    static func isSHA1(_ text: String) -> Bool {
        HexEncoding.isHex(text.uppercased(), length: 40, letterCase: .upper)
    }

    /// The Developer ID requirement of every signed file of `team`. A leading `=` makes codesign read it
    /// inline; the OID marks a Developer ID Application certificate.
    static func requirement(team: String) -> String {
        "=anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    }
}
