import Darwin
import Foundation
import JerdFoundation

extension ProcessRecoveryService {
    /// Signals the saved processes with the recorded graceful signal.
    ///
    /// A running leader: every live group member is verified and saved in the record first, so a
    /// second attempt can finish if Jerd exits during the stop. An exited leader: each saved
    /// descendant that still runs gets the same recorded signal.
    func requestStop(_ record: inout ActiveRunRecord, _ observation: ProcessObservation, at file: URL) throws {
        guard let identity = record.identity else {
            throw JerdError.unavailable("The old record has no verified process identity. Use manual recovery.")
        }
        if observation.master == .running {
            record.descendants = try verifiedMembers(record, identity)
            try ActiveRunRecordFile.write(record, to: file)
            try signaller.signal(identity, with: record.signal)
            return
        }
        for (member, match) in zip(record.descendants ?? [], observation.descendants) where match == .running {
            try signaller.signal(member, with: record.signal)
        }
    }

    /// The saved descendants plus every live group member, each verified as the same user's process.
    private func verifiedMembers(_ record: ActiveRunRecord, _ identity: ProcessIdentity) throws -> [ProcessIdentity] {
        let unverifiable = JerdError.unavailable("A service child cannot be verified. No process was signalled.")
        var members = record.descendants ?? []
        let pids: [pid_t]
        switch observer.groups.members(of: record.processID) {
        case .unknown:
            throw JerdError.unavailable("Cannot inspect all service processes. No process was signalled.")
        case .empty: pids = []
        case .members(let found): pids = found
        }
        for pid in pids where pid != record.processID {
            let child: ProcessIdentity
            do {
                child = try capture(pid)
            } catch {
                if observer.isGone(pid) { continue }
                throw unverifiable
            }
            guard child.userID == identity.userID, child.auditWords != nil else { throw unverifiable }
            if !members.contains(child) { members.append(child) }
        }
        return members
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
