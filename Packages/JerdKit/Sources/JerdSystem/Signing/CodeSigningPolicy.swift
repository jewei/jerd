import Foundation
import JerdFoundation
import Security

/// The code-signing rules of the XPC connection. Both sides require the peer to come from the
/// same Apple team, without the `get-task-allow` (debugger) entitlement.
///
/// The helper requires `dev.jerd.app` with its own team ID; the app requires `dev.jerd.helper`
/// with its own team ID. The requirement text is a compatibility contract.
public enum CodeSigningPolicy {
    /// Builds the requirement text for `identifier` (the app or the helper) and `teamID`.
    ///
    /// - Throws: `.invalid` when the team ID is not 10 uppercase letters or digits, the identifier
    ///   is not Jerd's, or Security cannot compile the text.
    public static func requirement(identifier: String, teamID: String) throws -> String {
        guard isValidTeamID(teamID),
            [HelperServiceIdentity.appIdentifier, HelperServiceIdentity.helperIdentifier].contains(identifier)
        else { throw JerdError.invalid("A valid Apple signing team is required for system setup.") }
        let text =
            "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
            + " and !entitlement[\"com.apple.security.get-task-allow\"] exists"
        var compiled: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &compiled) == errSecSuccess, compiled != nil else {
            throw JerdError.invalid("Cannot construct the helper signing requirement.")
        }
        return text
    }

    /// The team ID of the running binary.
    /// - Throws: `.unavailable` when the binary is not signed by an Apple team.
    public static func currentTeamID() throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        else {
            throw JerdError.unavailable(
                "System setup requires an Apple-signed Jerd build. Use the signed build instructions in README.")
        }
        return team
    }

    /// True for exactly 10 ASCII uppercase letters or digits.
    static func isValidTeamID(_ teamID: String) -> Bool {
        teamID.utf8.count == 10 && teamID.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
    }
}
