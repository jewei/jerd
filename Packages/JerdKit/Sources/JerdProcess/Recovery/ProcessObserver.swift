import Darwin

/// Takes one `ProcessObservation` of the live system for a record. Each identity is compared once.
public struct ProcessObserver: Sendable {
    /// Compares a saved identity with the live system.
    public typealias Match = @Sendable (ProcessIdentity) -> ProcessIdentity.Match
    /// True only when the PID is proven gone.
    public typealias IsGone = @Sendable (pid_t) -> Bool

    let match: Match
    let isGone: IsGone
    let groups: ProcessGroupInspector
    let auditedSignalsSupported: Bool

    public init(
        match: @escaping Match, isGone: @escaping IsGone, groups: ProcessGroupInspector,
        auditedSignalsSupported: Bool
    ) {
        self.match = match
        self.isGone = isGone
        self.groups = groups
        self.auditedSignalsSupported = auditedSignalsSupported
    }

    /// The live system: kernel identity checks, `proc_listpgrppids`, and run-time audited-signal support.
    public static let system = ProcessObserver(
        match: { $0.liveMatch() }, isGone: KernelProcessInfo.isGone, groups: ProcessGroupInspector(),
        auditedSignalsSupported: AuditedSignaller.system.isSupported)

    /// The same observer with another group inspector, for tests that simulate a failed inspection.
    public func with(groups: ProcessGroupInspector) -> ProcessObserver {
        ProcessObserver(match: match, isGone: isGone, groups: groups, auditedSignalsSupported: auditedSignalsSupported)
    }

    /// Observes every process that `record` names, once.
    public func observe(_ record: ActiveRunRecord) -> ProcessObservation {
        ProcessObservation(
            master: record.identity.map(match), controller: record.controller.map(match),
            descendants: (record.descendants ?? []).map(match),
            legacyLeaderGone: record.identity == nil && isGone(record.processID),
            group: groups.members(of: record.processID), currentUserID: geteuid(),
            auditedSignalsSupported: auditedSignalsSupported)
    }
}
