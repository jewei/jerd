import Darwin
import JerdSystem

/// Decides whether the helper accepts an XPC connection, before any message is read.
///
/// The code-signing requirement is checked by XPC itself (on the listener and on each connection).
/// This policy adds the owner rule: the peer's effective UID must be a regular account.
enum ConnectionAcceptPolicy {
    /// The result of the check, with the reason of a refusal for the log.
    enum Decision: Equatable {
        case accept
        case reject(reason: String)
    }

    static func decide(effectiveUserID: uid_t) -> Decision {
        guard OwnerPolicy.isEligible(effectiveUserID) else {
            return .reject(reason: "UID \(effectiveUserID) is below \(OwnerPolicy.minimumUserID)")
        }
        return .accept
    }
}
