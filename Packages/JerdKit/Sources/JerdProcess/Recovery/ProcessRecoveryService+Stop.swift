import Darwin
import Foundation
import JerdFoundation

extension ProcessRecoveryService {
    /// Signals the saved processes with the recorded graceful signal.
    ///
    /// A running leader: every live group member and every descendant that left the group is
    /// verified and saved in the record first, so a second attempt can finish if Jerd exits during
    /// the stop. An exited leader: each saved descendant that still runs gets the same recorded signal.
    /// Each signalled process and member then gets `SIGCONT`, so that a paused orphan can stop.
    func requestStop(
        _ record: inout ActiveRunRecord, _ observation: ProcessObservation, at location: RecordLocation,
        holding lock: InstanceLock
    ) throws {
        guard let identity = record.identity else {
            throw JerdError.unavailable("The old record has no verified process identity. Use manual recovery.")
        }
        if observation.master == .running {
            record.descendants = try verifiedMembers(record, identity)
            try ActiveRunRecordFile.write(record, at: location, holding: lock)
            try signaller.signal(identity, with: record.signal)
            try signaller.resume(identity)
            for member in record.descendants ?? [] { try signaller.resume(member) }
            return
        }
        for (member, match) in zip(record.descendants ?? [], observation.descendants) where match == .running {
            try signaller.signal(member, with: record.signal)
            try signaller.resume(member)
        }
    }

    /// The saved descendants plus every live group member and every live descendant by parent
    /// chain, each verified as the same user's process. A saved process is not added twice: the
    /// comparison uses `compare(with:)`, which ignores the boot time that a clock change moves.
    private func verifiedMembers(_ record: ActiveRunRecord, _ identity: ProcessIdentity) throws -> [ProcessIdentity] {
        let unverifiable = JerdError.unavailable("A service child cannot be verified. No process was signalled.")
        var members = record.descendants ?? []
        for pid in try livePIDs(record) where pid != record.processID {
            let child: ProcessIdentity
            do {
                child = try capture(pid)
            } catch {
                if observer.isGone(pid) { continue }
                throw unverifiable
            }
            guard child.userID == identity.userID, child.auditWords != nil else { throw unverifiable }
            if !members.contains(where: { $0.compare(with: child) == .running }) { members.append(child) }
        }
        return members
    }

    /// The group members of the record's leader and the descendants that left the group, sorted.
    private func livePIDs(_ record: ActiveRunRecord) throws -> [pid_t] {
        let incomplete = JerdError.unavailable("Cannot inspect all service processes. No process was signalled.")
        var pids: Set<pid_t> = []
        switch observer.groups.members(of: record.processID) {
        case .unknown: throw incomplete
        case .empty: break
        case .members(let found): pids.formUnion(found)
        }
        guard let descendants = observer.tree.descendants(of: [record.processID] + pids.sorted()) else {
            throw incomplete
        }
        pids.formUnion(descendants.map(\.processID))
        return pids.sorted()
    }

    /// Polls until the record is stale. Never escalates to `SIGKILL`.
    func waitUntilStale(_ record: ActiveRunRecord, deadline: ContinuousClock.Instant) async throws {
        while !RecoveryClassifier.isStale(record, observer.observe(record)) {
            guard ContinuousClock.now < deadline else {
                throw JerdError.unavailable(
                    "The service has not stopped safely. Its process record and data were preserved. "
                        + "Retry recovery after checking its log.")
            }
            try await Task.sleep(for: pollInterval)
        }
    }
}
