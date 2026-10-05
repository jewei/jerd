import Darwin
import JerdProcess

/// Builds identities for pure recovery tests.
enum IdentityFactory {
    static func make(
        pid: Int32 = 4_242, user: UInt32 = geteuid(), started: UInt64 = 100, micro: UInt64 = 5, boot: Int64 = 50,
        executable: String = "/bin/x", audit: [UInt32]? = [1, 2, 3, 4, 5, 6, 7, 8], session: String? = "SESSION-A"
    ) -> ProcessIdentity {
        ProcessIdentity(
            processID: pid, userID: user, startedSeconds: started, startedMicroseconds: micro, bootSeconds: boot,
            executable: executable, auditWords: audit, bootSessionID: session)
    }

    /// The same identity with a later start time: the PID now names another process.
    static func differentStart(_ identity: ProcessIdentity) -> ProcessIdentity {
        ProcessIdentity(
            processID: identity.processID, userID: identity.userID, startedSeconds: identity.startedSeconds + 1,
            startedMicroseconds: identity.startedMicroseconds, bootSeconds: identity.bootSeconds,
            executable: identity.executable, auditWords: identity.auditWords, bootSessionID: identity.bootSessionID)
    }
}
