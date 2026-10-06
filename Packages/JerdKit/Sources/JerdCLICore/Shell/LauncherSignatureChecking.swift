import Foundation

/// Checks the code signature of the launcher copy before it goes into the user's PATH.
public protocol LauncherSignatureChecking: Sendable {
    /// - Throws: `.invalid` when the file has no valid code signature.
    func checkSignature(of file: URL) throws
}
