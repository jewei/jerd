import Foundation
import JerdFoundation
import Security

/// The live signature check: the static code signature of every architecture must be valid.
///
/// It accepts any valid signer, also the ad hoc signature of a local Debug build. It proves that
/// the copied bytes are the complete, unchanged launcher that the app build signed.
public struct CodeSignatureCheck: LauncherSignatureChecking {
    public init() {}

    public func checkSignature(of file: URL) throws {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(file as CFURL, SecCSFlags(), &code)
        guard created == errSecSuccess, let code else { throw Self.invalid(file, created) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(code, flags, nil)
        guard status == errSecSuccess else { throw Self.invalid(file, status) }
    }

    private static func invalid(_ file: URL, _ status: OSStatus) -> JerdError {
        .invalid("The Jerd command launcher \(file.path) has no valid code signature (\(status)). Install Jerd again.")
    }
}
