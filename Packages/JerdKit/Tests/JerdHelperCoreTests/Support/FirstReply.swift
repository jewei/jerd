import Foundation

/// The first of a reply and a deadline. A reply that never comes gives nil instead of a hung test.
enum FirstReply {
    static func within<Value: Sendable>(
        _ deadline: Duration, _ send: (@escaping @Sendable (Value) -> Void) -> Void
    ) async -> Value? {
        let (stream, continuation) = AsyncStream<Value?>.makeStream()
        send { continuation.yield($0) }
        let timer = Task {
            try? await Task.sleep(for: deadline)
            continuation.yield(nil)
        }
        defer { timer.cancel() }
        for await value in stream { return value }
        return nil
    }
}
