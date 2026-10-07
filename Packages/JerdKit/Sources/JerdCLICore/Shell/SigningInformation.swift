import Foundation
import Security

/// The signing facts of one piece of code that the launcher check needs: its Team ID and ad hoc flag.
struct SigningInformation: Equatable, Sendable {
    let teamIdentifier: String?
    let isAdHoc: Bool

    /// The signer that a launcher must match. Without a Team ID (ad hoc, unsigned, or a platform
    /// binary such as a test runner) only an ad hoc launcher passes. Pure.
    var signer: CodeSignatureCheck.Signer {
        guard let teamIdentifier, !teamIdentifier.isEmpty, !isAdHoc else { return .adHoc }
        return .team(teamIdentifier)
    }

    /// The facts of the running process; an unsigned process gives no Team ID.
    static func ofRunningProcess() -> SigningInformation {
        var code: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode
        else { return SigningInformation(teamIdentifier: nil, isAdHoc: false) }
        return of(staticCode)
    }

    /// The facts of `code` from its signature.
    static func of(_ code: SecStaticCode) -> SigningInformation {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
            let values = information as? [String: Any]
        else { return SigningInformation(teamIdentifier: nil, isAdHoc: false) }
        let codeFlags = (values[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return SigningInformation(
            teamIdentifier: values[kSecCodeInfoTeamIdentifier as String] as? String,
            isAdHoc: codeFlags & SecCodeSignatureFlags.adhoc.rawValue != 0)
    }
}
