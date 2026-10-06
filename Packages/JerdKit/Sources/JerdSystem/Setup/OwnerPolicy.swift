import Darwin
import JerdFoundation

/// The one rule for the user that may own a helper setup: a regular account (UID 501 or higher).
///
/// The helper uses it to accept a connection, and the setup store uses it again for every
/// operation, so a lower UID can never own a registration or a recovery record.
public enum OwnerPolicy {
    /// The lowest UID of a regular macOS account.
    public static let minimumUserID: uid_t = 501

    /// True when `uid` may own a setup.
    public static func isEligible(_ uid: uid_t) -> Bool { uid >= minimumUserID }

    /// Throws unless `uid` may own a setup.
    public static func require(_ uid: uid_t) throws {
        guard uid != 0 else { throw JerdError.invalid("Root cannot own a Jerd project environment.") }
        guard isEligible(uid) else {
            throw JerdError.invalid("Jerd system setup needs a regular user account (UID 501 or higher).")
        }
    }
}
