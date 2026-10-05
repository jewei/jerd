import Darwin

/// One snapshot of the live system for one record. Every rule reads the same snapshot, so a
/// classification cannot mix states from different moments.
public struct ProcessObservation: Equatable, Sendable {
    /// The match of `record.identity`, or nil when the record has none.
    public var master: ProcessIdentity.Match?
    /// The match of `record.controller`, or nil when the record has none.
    public var controller: ProcessIdentity.Match?
    /// The matches of `record.descendants`, in the same order.
    public var descendants: [ProcessIdentity.Match]
    /// For records without an identity: true only when `kill(pid, 0)` proved that the PID is gone.
    public var legacyLeaderGone: Bool
    /// The live members of the group that the record's PID led.
    public var group: ProcessGroupInspector.Membership
    /// The user that runs Jerd now.
    public var currentUserID: uid_t
    /// True when audited signals are available.
    public var auditedSignalsSupported: Bool

    public init(
        master: ProcessIdentity.Match?, controller: ProcessIdentity.Match?, descendants: [ProcessIdentity.Match],
        legacyLeaderGone: Bool, group: ProcessGroupInspector.Membership, currentUserID: uid_t,
        auditedSignalsSupported: Bool
    ) {
        self.master = master
        self.controller = controller
        self.descendants = descendants
        self.legacyLeaderGone = legacyLeaderGone
        self.group = group
        self.currentUserID = currentUserID
        self.auditedSignalsSupported = auditedSignalsSupported
    }
}
