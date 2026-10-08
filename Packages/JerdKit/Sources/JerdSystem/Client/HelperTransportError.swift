import Foundation
import JerdFoundation

/// A call that did not reach the helper or whose reply XPC refused, with its cause.
///
/// `HelperClient` decides from the cause whether it retries; every error that leaves the client
/// is the `JerdError` of `userError`, never this type.
struct HelperTransportError: Error, LocalizedError, Equatable, Sendable {
    /// What the XPC error says about the helper.
    enum Cause: Equatable, Sendable {
        /// The helper process does not satisfy the code-signing requirement: usually a helper that
        /// ran before an app update and still runs the old code (`NSXPCConnectionCodeSigningRequirementFailure`).
        case signatureMismatch
        /// The connection closed or could not open, for example while an idle helper exits.
        case connectionLost
        /// Any other transport failure.
        case other
    }

    /// `NSXPCConnectionInterrupted`, `NSXPCConnectionInvalid`, and
    /// `NSXPCConnectionCodeSigningRequirementFailure`.
    static let interruptedCode = 4_097
    static let invalidCode = 4_099
    static let signatureCode = 4_102
    /// `errSecCSReqFailed`: the code does not satisfy the requirement.
    static let requirementFailedStatus = -67_050

    let cause: Cause
    let domain: String
    let code: Int

    init(_ error: any Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
        cause = Self.classify(domain: error.domain, code: error.code)
    }

    static func classify(domain: String, code: Int) -> Cause {
        switch (domain, code) {
        case (NSCocoaErrorDomain, signatureCode), (NSOSStatusErrorDomain, requirementFailedStatus):
            .signatureMismatch
        case (NSCocoaErrorDomain, interruptedCode), (NSCocoaErrorDomain, invalidCode): .connectionLost
        default: .other
        }
    }

    /// The domain and code for the end of a message, so a report names the exact failure.
    var reference: String { "(\(domain) \(code))" }

    /// The message when Jerd cannot reach its helper; the page offers Reconnect Helper….
    var userError: JerdError {
        JerdError.unavailable(
            "Jerd could not communicate with its system helper. Click Reconnect Helper…, or choose it in the "
                + "System Setup menu (the shield button in the Sites toolbar). Host entries and certificate "
                + "settings stay. \(reference)"
        ).with(.reconnectHelper)
    }

    var errorDescription: String? { userError.message }
}
