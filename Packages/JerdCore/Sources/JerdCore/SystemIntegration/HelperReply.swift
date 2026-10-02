import Foundation

/// Bridges helper callbacks to one result, including cancellation before registration.
public final class HelperReply<Value: Sendable>: @unchecked Sendable {
    public enum CancellationPolicy: Sendable {
        case readOnly
        /// A request that changes state must finish or report a transport failure.
        case awaitReply
    }

    private enum State {
        case unregistered
        case waiting(CheckedContinuation<Value, any Error>)
        case resolved(Result<Value, any Error>)
        case finished
    }
    private let lock = NSLock()
    private var state: State = .unregistered
    private var watchdog: Task<Void, Never>?
    private init() {}

    public static func wait(cancellation: CancellationPolicy, timeout: Duration? = .seconds(20),
                            isolation: isolated (any Actor)? = #isolation,
                            onTimeout: @escaping @Sendable () async -> Void = {},
                            send: (HelperReply<Value>) -> Void) async throws -> Value {
        let reply = HelperReply<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard reply.register(continuation) else { return }
                if let timeout {
                    let timer = Task {
                        do { try await Task.sleep(for: timeout) }
                        catch { return }
                        if reply.resolve(.failure(JerdError.unavailable("The helper did not reply. Check macOS approval and try again."))) {
                            await onTimeout()
                        }
                    }
                    reply.setWatchdog(timer)
                }
                send(reply)
            }
        } onCancel: {
            if cancellation == .readOnly { reply.resolve(.failure(CancellationError())) }
        }
    }

    /// A reply, transport failure, timeout, or cancellation can win only once.
    @discardableResult public func resolve(_ result: Result<Value, any Error>) -> Bool {
        lock.lock()
        let continuation: CheckedContinuation<Value, any Error>?
        switch state {
        case .unregistered: state = .resolved(result); continuation = nil
        case .waiting(let current): state = .finished; continuation = current
        case .resolved, .finished: lock.unlock(); return false
        }
        let timer = watchdog
        watchdog = nil
        lock.unlock()
        timer?.cancel()
        continuation?.resume(with: result)
        return true
    }

    private func register(_ continuation: CheckedContinuation<Value, any Error>) -> Bool {
        lock.lock()
        if case .resolved(let result) = state {
            state = .finished
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        state = .waiting(continuation)
        lock.unlock()
        return true
    }

    private func setWatchdog(_ timer: Task<Void, Never>) {
        let pending = lock.withLock {
            guard case .waiting = state else { return false }
            watchdog = timer
            return true
        }
        if !pending { timer.cancel() }
    }
}
