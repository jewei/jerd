import JerdFoundation
import JerdServiceKit
import os

/// Scripted readiness answers, one per probe. `.ready` when the script is empty.
final class ProbeScript: Sendable {
    enum Answer: Sendable {
        case ready
        case notReady(String)
        case failure(JerdError)
    }

    private let answers = OSAllocatedUnfairLock<[Answer]>(initialState: [])
    private let count = OSAllocatedUnfairLock(initialState: 0)
    private let hook = OSAllocatedUnfairLock<(@Sendable () async -> Void)?>(initialState: nil)

    var calls: Int { count.withLock { $0 } }

    func set(_ script: [Answer]) { answers.withLock { $0 = script } }

    /// Repeats `answer` for every later probe.
    func always(_ answer: Answer) { answers.withLock { $0 = Array(repeating: answer, count: 10_000) } }

    /// Runs `action` at the start of every probe, for example to end the fake process.
    func setHook(_ action: @escaping @Sendable () async -> Void) { hook.withLock { $0 = action } }

    func next() async throws -> ReadinessCheck.ProbeResult {
        count.withLock { $0 += 1 }
        if let action = hook.withLock({ $0 }) { await action() }
        let answer = answers.withLock { $0.isEmpty ? Answer.ready : $0.removeFirst() }
        switch answer {
        case .ready: return .ready
        case .notReady(let text): return .notReady(text)
        case .failure(let error): throw error
        }
    }
}
