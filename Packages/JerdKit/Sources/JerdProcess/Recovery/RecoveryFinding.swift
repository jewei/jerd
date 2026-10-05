/// One row of Advanced → Process recovery.
public struct RecoveryFinding: Identifiable, Equatable, Sendable {
    /// What recovery can do with a record.
    public enum State: Equatable, Sendable {
        /// The saved processes are gone. Clearing the record is safe.
        case stale
        /// Ownership is verified. Recovery can request a graceful stop.
        case recoverable
        /// A running Jerd session owns the process. Use its normal Stop control.
        case managed
        /// Ownership is uncertain or the record cannot be read. Jerd sends no signal.
        case manual

        /// True for `stale` and `recoverable`.
        public var canRecover: Bool { self == .stale || self == .recoverable }
    }

    /// The record ID, for example `Database/<UUID>`. Pass it to `ProcessRecoveryService.recover(_:)`.
    public let id: String
    /// A short name, for example "Mail" or "Database 1F3A0000".
    public let title: String
    public let detail: String
    public let state: State

    public init(id: String, title: String, detail: String, state: State) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
    }

    public var canRecover: Bool { state.canRecover }
}
