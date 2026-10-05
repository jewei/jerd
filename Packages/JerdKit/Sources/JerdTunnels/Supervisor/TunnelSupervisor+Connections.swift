import Foundation
import JerdFoundation

extension TunnelSupervisor {
    /// Launches a connector and then monitors it. Returns when the process runs, not when it is
    /// connected. A launch failure is shown on the tunnel and thrown; it is not retried.
    public func start(id: UUID) async throws {
        try requireLoaded()
        guard !editing, !shuttingDown else { throw JerdError.unavailable(TunnelMessage.busy) }
        guard let registration = configuration.registration(id) else {
            throw JerdError.invalid(TunnelMessage.notRegistered)
        }
        guard !isActive(id) else { throw JerdError.unavailable(TunnelMessage.alreadyActive) }
        guard configuration.runtime != nil else { throw JerdError.unavailable(TunnelMessage.runtimeMissing) }
        let generation = makeGeneration()
        apply(.connectRequested(generation, restartOnFailure: registration.restartOnFailure), to: id)
        let launch = Task { await self.launch(id, generation) }
        work[id] = TunnelWork(generation: generation, task: launch)
        let progress = await launch.value
        // Only the owner of this generation may clear or replace the slot.
        if work[id]?.generation == generation { work[id] = nil }
        let step = apply(.progress(generation, progress), to: id)
        if case .launchFailed(let failure) = progress { throw failure.error }
        guard isCurrent(generation, id) else { throw JerdError.unavailable(TunnelMessage.cancelled) }
        let monitor = Task { await self.drive(id, generation, from: step) }
        work[id] = TunnelWork(generation: generation, task: monitor)
    }

    /// Stops the connector gracefully. Concurrent Stops share one operation, and a new Connect
    /// waits until it is done. A connector that does not stop stays owned, and the error is thrown.
    public func stop(id: UUID) async throws {
        if let running = stops[id] { return try await running.task.value }
        let ticket = UUID()
        let task = Task { try await self.performStop(id) }
        stops[id] = TunnelStopWork(ticket: ticket, task: task)
        let result = await task.result
        if stops[id]?.ticket == ticket { stops[id] = nil }
        try result.get()
    }

    /// Stops every connector at the same time, for Quit. Throws with every failure, one per line,
    /// so that the app cancels Quit while a connector still runs.
    public func stopAll() async throws {
        shuttingDown = true
        defer { shuttingDown = false }
        let order = configuration.tunnels.map(\.id)
        let extra = Set(handles.keys).union(work.keys).subtracting(order)
        let ids = order + extra.sorted { $0.uuidString < $1.uuidString }
        let failures = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    do {
                        try await self.stop(id: id)
                        return (index, nil)
                    } catch {
                        return (index, FailureDetail.describe(error))
                    }
                }
            }
            var messages: [(Int, String)] = []
            for await (index, message) in group { if let message { messages.append((index, message)) } }
            return messages.sorted { $0.0 < $1.0 }.map(\.1)
        }
        guard failures.isEmpty else { throw JerdError.processFailed(failures.joined(separator: "\n")) }
    }

    /// Connects every registration with `startOnLaunch`, one after another. Every failure is kept.
    public func connectStartupTunnels() async throws -> [TunnelStartupFailure] {
        try requireLoaded()
        var failures: [TunnelStartupFailure] = []
        for registration in configuration.tunnels where registration.startOnLaunch {
            guard !shuttingDown else { break }
            do {
                try await start(id: registration.id)
            } catch {
                failures.append(
                    TunnelStartupFailure(
                        id: registration.id, name: registration.name, message: FailureDetail.describe(error)))
            }
        }
        return failures
    }

    /// Ends the generation, waits for its work, then stops the owned connector.
    private func performStop(_ id: UUID) async throws {
        apply(.stopRequested, to: id)
        if let current = work.removeValue(forKey: id) {
            current.cancel()
            await current.finished()
        }
        do {
            if let handle = handles[id] {
                try await connector.disconnect(handle)
                if handles[id] == handle { handles[id] = nil }
            }
            apply(.stopFinished(error: nil), to: id)
        } catch {
            apply(.stopFinished(error: FailureDetail.describe(error)), to: id)
            throw error
        }
    }
}
