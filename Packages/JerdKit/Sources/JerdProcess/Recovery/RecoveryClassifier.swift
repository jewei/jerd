import Darwin

/// The pure recovery rules: when a record is stale, and what recovery may do with it.
public enum RecoveryClassifier {
    /// True when no saved process can still use the service data.
    ///
    /// - With an identity: the leader and every saved descendant exited or were replaced, and
    ///   either the leader PID was replaced or its group is proven empty. (macOS does not give a
    ///   new process a PID that is still a group ID, so a replaced PID proves the group is gone.)
    /// - Without an identity: the PID is proven gone and its group is proven empty.
    public static func isStale(_ record: ActiveRunRecord, _ observation: ProcessObservation) -> Bool {
        guard let master = observation.master else {
            return observation.legacyLeaderGone && observation.group == .empty
        }
        let gone: Set<ProcessIdentity.Match> = [.exited, .replaced]
        guard gone.contains(master), observation.descendants.allSatisfy(gone.contains) else { return false }
        return master == .replaced || observation.group == .empty
    }

    /// True when a live group member is not a recorded identity that still runs.
    public static func hasUnverifiedGroupMembers(_ record: ActiveRunRecord, _ observation: ProcessObservation) -> Bool {
        if observation.master == .replaced { return false }
        let members: [pid_t]
        switch observation.group {
        case .unknown: return true
        case .empty: members = []
        case .members(let pids): members = pids
        }
        var verified: Set<pid_t> = []
        if observation.master == .running, let identity = record.identity { verified.insert(identity.processID) }
        for (descendant, match) in zip(record.descendants ?? [], observation.descendants) where match == .running {
            verified.insert(descendant.processID)
        }
        return members.contains { !verified.contains($0) }
    }

    /// A classification: the row state and its user detail.
    public struct Verdict: Equatable, Sendable {
        public let state: RecoveryFinding.State
        public let detail: String

        public init(state: RecoveryFinding.State, detail: String) {
            self.state = state
            self.detail = detail
        }
    }

    /// Classifies a record. The first matching rule wins: stale, legacy, managed, recoverable, manual.
    public static func classify(_ record: ActiveRunRecord, _ observation: ProcessObservation) -> Verdict {
        let pid = record.processID
        if isStale(record, observation) {
            return Verdict(state: .stale, detail: RecoveryMessages.stale)
        }
        guard let identity = record.identity, record.controller != nil else {
            return Verdict(state: .manual, detail: RecoveryMessages.legacy(pid))
        }
        if observation.controller == .running {
            return Verdict(state: .managed, detail: RecoveryMessages.managed(pid))
        }
        guard isRecoverable(record, identity, observation) else {
            return Verdict(state: .manual, detail: RecoveryMessages.uncertain(pid))
        }
        return Verdict(state: .recoverable, detail: RecoveryMessages.recoverable(record, identity))
    }

    private static func isRecoverable(
        _ record: ActiveRunRecord, _ identity: ProcessIdentity, _ observation: ProcessObservation
    ) -> Bool {
        guard let controller = observation.controller, controller == .exited || controller == .replaced,
            let master = observation.master, master != .unknown, !observation.descendants.contains(.unknown)
        else { return false }
        return identity.userID == observation.currentUserID && observation.auditedSignalsSupported
            && identity.auditWords != nil
            && (master == .running || !hasUnverifiedGroupMembers(record, observation))
    }
}
