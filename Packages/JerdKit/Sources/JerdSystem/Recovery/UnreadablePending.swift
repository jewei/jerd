import JerdFoundation

/// A `pending.json` that cannot be read, decoded, or validated, with its report for the user.
struct UnreadablePending: Error, Sendable {
    let error: JerdError
    let report: SystemRecoveryStatus
}
