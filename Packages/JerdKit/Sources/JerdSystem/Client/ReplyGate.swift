import Foundation
import JerdFoundation
import os

/// Turns one XPC reply callback into one async result. A reply, a transport error, a timeout, or a
/// cancellation can win, but only once; later results return false from `resolve`.
///
/// States: unregistered → waiting → finished, or unregistered → resolved → finished (a result that
/// arrives before registration). `send` is never called once the gate is resolved, also not after a
/// cancellation between registration and sending.
public final class ReplyGate<Value: Sendable>: Sendable {
    /// What task cancellation does to a waiting call.
    public enum CancellationPolicy: Sendable {
        /// A read-only call ends at once with `CancellationError`.
        case readOnly
        /// A call that changes state waits for its reply, a transport error, or its timeout.
        case awaitReply
    }

    /// The error of a call that did not get a reply in time.
    public static var timeoutError: JerdError {
        .unavailable("The helper did not reply. Check macOS approval and try again.")
    }

    private enum State: Sendable {
        case unregistered
        case waiting(CheckedContinuation<Value, any Error>)
        case resolved(Result<Value, any Error>)
        case finished
    }

    private struct Guarded: Sendable {
        var state = State.unregistered
        var watchdog: Task<Void, Never>?
    }

    private let guarded = OSAllocatedUnfairLock(initialState: Guarded())

    private init() {}

    /// Waits for the result of one call.
    ///
    /// - Parameters:
    ///   - timeout: nil means no app timeout (for calls that wait for a macOS approval prompt).
    ///   - onTimeout: runs after the caller resumed, only when the timeout won.
    ///   - send: sends the request; it receives the gate to resolve.
    public static func wait(
        cancellation: CancellationPolicy, timeout: Duration?, isolation: isolated (any Actor)? = #isolation,
        onTimeout: @escaping @Sendable () async -> Void = {}, send: (ReplyGate<Value>) -> Void
    ) async throws -> Value {
        let gate = ReplyGate<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.register(continuation) else { return }
                if let timeout { gate.startWatchdog(timeout, onTimeout: onTimeout) }
                if gate.isWaiting { send(gate) }
            }
        } onCancel: {
            if cancellation == .readOnly { gate.resolve(.failure(CancellationError())) }
        }
    }

    /// Delivers `result` if nothing won before. Returns false for a late result.
    @discardableResult public func resolve(_ result: Result<Value, any Error>) -> Bool {
        typealias Win = (continuation: CheckedContinuation<Value, any Error>?, watchdog: Task<Void, Never>?)
        let win = guarded.withLock { current -> Win? in
            let continuation: CheckedContinuation<Value, any Error>?
            switch current.state {
            case .resolved, .finished: return nil
            case .unregistered:
                current.state = .resolved(result)
                continuation = nil
            case .waiting(let waiting):
                current.state = .finished
                continuation = waiting
            }
            defer { current.watchdog = nil }
            return (continuation, current.watchdog)
        }
        guard let win else { return false }
        // The watchdog is cancelled outside the lock; a completed call releases it before its deadline.
        win.watchdog?.cancel()
        win.continuation?.resume(with: result)
        return true
    }

    private var isWaiting: Bool {
        guarded.withLock { current in
            if case .waiting = current.state { return true }
            return false
        }
    }

    private func register(_ continuation: CheckedContinuation<Value, any Error>) -> Bool {
        let early = guarded.withLock { current -> Result<Value, any Error>? in
            if case .resolved(let result) = current.state {
                current.state = .finished
                return result
            }
            current.state = .waiting(continuation)
            return nil
        }
        guard let early else { return true }
        continuation.resume(with: early)
        return false
    }

    private func startWatchdog(_ timeout: Duration, onTimeout: @escaping @Sendable () async -> Void) {
        let watchdog = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            if self?.resolve(.failure(Self.timeoutError)) == true { await onTimeout() }
        }
        let installed = guarded.withLock { current -> Bool in
            guard case .waiting = current.state else { return false }
            current.watchdog = watchdog
            return true
        }
        if !installed { watchdog.cancel() }
    }
}
