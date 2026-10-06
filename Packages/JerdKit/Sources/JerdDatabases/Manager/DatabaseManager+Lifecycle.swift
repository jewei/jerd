import Foundation
import JerdFoundation
import JerdServiceKit

extension DatabaseManager {
    /// Starts one service. Errors keep the kind of the failed step.
    public func start(_ id: UUID) async throws {
        let service = try lookup(id)
        guard !operations.contains(id) else { throw JerdError.unavailable(DatabaseMessages.busy) }
        try await instance(for: service).start()
    }

    /// Stops one service gracefully. A stop that exit detection began is joined.
    public func stop(_ id: UUID) async throws {
        _ = try lookup(id)
        guard !operations.contains(id) else { throw JerdError.unavailable(DatabaseMessages.busy) }
        try await instances[id]?.stop()
    }

    /// Stops every service in parallel for Quit. Any failure cancels Quit.
    ///
    /// Only a start, Edit, Remove, or Restore in progress refuses Quit. An exit stop in progress
    /// is joined, so a crashed server never cancels Quit by mistake.
    ///
    /// It does not need loaded settings: it stops every instance that this manager owns. Without
    /// a load there is none. A load failure (for example corrupt settings) stays the error of
    /// `load()`, so it never blocks Quit.
    public func stopAll() async throws {
        guard operations.isEmpty else { throw DatabaseMessages.quitBusy }
        let all = Array(instances.values)
        for instance in all where await instance.state == .starting { throw DatabaseMessages.quitBusy }
        let failures = await withTaskGroup(of: String?.self) { group in
            for instance in all {
                group.addTask {
                    do {
                        try await instance.stop()
                        return nil
                    } catch {
                        return FailureDetail.describe(error)
                    }
                }
            }
            var messages: [String] = []
            for await message in group { if let message { messages.append(message) } }
            return messages.sorted()
        }
        guard failures.isEmpty else { throw JerdError.processFailed(failures.joined(separator: "\n")) }
    }
}
