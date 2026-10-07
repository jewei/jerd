import Foundation
import JerdFoundation
import Security

/// The live signature check: the launcher must have a valid signature from the same signer as the app.
///
/// For a signed app, the launcher must satisfy `anchor apple generic` with the app's Team ID, so a
/// file that another developer or an ad hoc signer made is refused. For an ad hoc or unsigned app (a
/// local development build), only an ad hoc launcher passes. A valid signature proves that the bytes
/// are complete and unchanged since that signer signed them; it does not prove which build made them.
package struct CodeSignatureCheck: LauncherSignatureChecking {
    /// The signer that the launcher must have.
    package enum Signer: Equatable, Sendable {
        /// A Developer ID or Apple Development signature with this Team ID.
        case team(String)
        /// An ad hoc signature, for development builds only.
        case adHoc
    }

    package let expected: Signer

    package init(expected: Signer) {
        self.expected = expected
    }

    /// The check for the signer of the running app.
    package static func forRunningApp() -> CodeSignatureCheck {
        CodeSignatureCheck(expected: SigningInformation.ofRunningProcess().signer)
    }

    package func checkSignature(of file: URL) throws {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(file as CFURL, SecCSFlags(), &code)
        guard created == errSecSuccess, let code else { throw Self.invalid(file, created) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(code, flags, try requirement())
        guard status == errSecSuccess else { throw Self.invalid(file, status) }
        if expected == .adHoc, !SigningInformation.of(code).isAdHoc {
            throw JerdError.invalid(
                "The Jerd command launcher \(file.path) is not ad hoc signed like this development build. "
                    + "Build Jerd again.")
        }
    }

    /// The code requirement for a team signer; nil for ad hoc, which has no certificate to check.
    private func requirement() throws -> SecRequirement? {
        guard case .team(let team) = expected else { return nil }
        guard Self.isTeamIdentifier(team) else {
            throw JerdError.invalid("The Team ID \(team) of this Jerd app is not valid. Install Jerd again.")
        }
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString
        guard SecRequirementCreateWithString(text, SecCSFlags(), &requirement) == errSecSuccess, let requirement
        else { throw JerdError.invalid("Cannot build the signature requirement for Team ID \(team).") }
        return requirement
    }

    /// A Team ID is ten uppercase letters or digits; anything else cannot go into a requirement.
    static func isTeamIdentifier(_ text: String) -> Bool {
        text.utf8.count == 10 && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) }
    }

    private static func invalid(_ file: URL, _ status: OSStatus) -> JerdError {
        .invalid(
            "The Jerd command launcher \(file.path) has no valid code signature from this app's signer (\(status)). "
                + "Install Jerd again.")
    }
}
