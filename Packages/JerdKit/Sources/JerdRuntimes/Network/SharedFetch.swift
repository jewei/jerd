import Foundation
import os

/// One in-flight fetch that several waiters share (fixes RT-2).
///
/// A cancelled waiter stops waiting at once and gets `CancellationError`. The fetch goes on for the
/// other waiters. When the last waiter leaves, the fetch is cancelled and marked abandoned, so a new
/// request starts a new fetch instead of joining the cancelled one.
final class SharedFetch: Sendable {
    private struct State: Sendable {
        var members: Set<UUID> = []
        var waiting: [UUID: CheckedContinuation<Data, any Error>] = [:]
        var result: Result<Data, any Error>?
        var task: Task<Void, Never>?
        var isAbandoned = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// True after the last waiter left before the fetch ended.
    var isAbandoned: Bool { state.withLock { $0.isAbandoned } }

    /// The waiters that have not left.
    var waiterCount: Int { state.withLock { $0.members.count } }

    /// Keeps the task that runs the fetch, so the last leaving waiter can cancel it.
    func attach(_ task: Task<Void, Never>) {
        let cancel = state.withLock { state in
            state.task = task
            return state.isAbandoned
        }
        if cancel { task.cancel() }
    }

    /// Adds a waiter. Call it before `value(for:)`, in the same isolation step as the lookup.
    func join() -> UUID {
        let id = UUID()
        state.withLock { _ = $0.members.insert(id) }
        return id
    }

    /// The fetched bytes. A cancellation of the calling task ends only this wait.
    func value(for id: UUID) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let ready: Result<Data, any Error>? = state.withLock { state in
                    if let result = state.result { return result }
                    guard state.members.contains(id) else { return .failure(CancellationError()) }
                    state.waiting[id] = continuation
                    return nil
                }
                if let ready { continuation.resume(with: ready) }
            }
        } onCancel: {
            leave(id)
        }
    }

    /// Ends the fetch and resumes every waiter with its result.
    func finish(_ result: Result<Data, any Error>) {
        let waiting = state.withLock { state in
            state.result = result
            defer { state.waiting = [:] }
            return Array(state.waiting.values)
        }
        for continuation in waiting { continuation.resume(with: result) }
    }

    private func leave(_ id: UUID) {
        let (continuation, task) = state.withLock {
            state -> (CheckedContinuation<Data, any Error>?, Task<Void, Never>?) in
            guard state.result == nil, state.members.remove(id) != nil else { return (nil, nil) }
            let continuation = state.waiting.removeValue(forKey: id)
            guard state.members.isEmpty else { return (continuation, nil) }
            state.isAbandoned = true
            return (continuation, state.task)
        }
        continuation?.resume(throwing: CancellationError())
        task?.cancel()
    }
}
