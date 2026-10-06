import Foundation
import JerdFoundation
import Testing
import os

@testable import JerdSystem

@Suite struct ReplyGateTests {
    private actor Counter {
        var count = 0
        func add() { count += 1 }
    }

    private final class Released: Sendable {
        let flag = OSAllocatedUnfairLock(initialState: false)
    }

    private final class Capture: Sendable {
        let released: Released
        init(_ released: Released) { self.released = released }
        func timedOut() { Issue.record("A completed request reached its timeout hook.") }
        deinit { released.flag.withLock { $0 = true } }
    }

    @Test func aCancelledReadOnlyCallEndsPromptlyAndIgnoresLateReplies() async throws {
        let (gates, sent) = AsyncStream<ReplyGate<Int>>.makeStream()
        let timeouts = Counter()
        let task = Task {
            try await ReplyGate<Int>.wait(
                cancellation: .readOnly, timeout: .seconds(1), onTimeout: { await timeouts.add() }
            ) {
                sent.yield($0)
                sent.finish()
            }
        }
        let gate = try #require(await gates.first { _ in true })
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - start < .milliseconds(500))
        #expect(!gate.resolve(.success(42)))
        #expect(!gate.resolve(.failure(JerdError.unavailable("late"))))
        #expect(await timeouts.count == 0)
    }

    @Test func aCallCancelledBeforeRegistrationIsNeverSent() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ReplyGate<Int>.wait(cancellation: .readOnly, timeout: nil) { gate in
                Issue.record("A cancelled request was sent.")
                gate.resolve(.success(42))
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(arguments: [false, true])
    func aChangingCallWaitsForItsReplyDespiteCancellation(cancelBeforeSend: Bool) async throws {
        let (gates, sent) = AsyncStream<ReplyGate<Int>>.makeStream()
        let task = Task {
            if cancelBeforeSend { withUnsafeCurrentTask { $0?.cancel() } }
            return try await ReplyGate<Int>.wait(cancellation: .awaitReply, timeout: nil) {
                sent.yield($0)
                sent.finish()
            }
        }
        let gate = try #require(await gates.first { _ in true })
        task.cancel()
        #expect(gate.resolve(.success(42)))
        #expect(try await task.value == 42)
        #expect(!gate.resolve(.success(43)))
    }

    @Test func aTimeoutFailsOnceAndRunsItsHookAfterTheCallerResumes() async throws {
        let timeouts = Counter()
        await #expect(throws: ReplyGate<Int>.timeoutError) {
            try await ReplyGate<Int>.wait(
                cancellation: .readOnly, timeout: .milliseconds(20), onTimeout: { await timeouts.add() }, send: { _ in }
            )
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while await timeouts.count == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await timeouts.count == 1)
        let value = try await ReplyGate<Int>.wait(
            cancellation: .awaitReply, timeout: .milliseconds(20), onTimeout: { await timeouts.add() },
            send: { $0.resolve(.success(42)) })
        #expect(value == 42)
        try await Task.sleep(for: .milliseconds(60))
        #expect(await timeouts.count == 1)
    }

    @Test func aCompletedCallReleasesItsWatchdogBeforeTheDeadline() async throws {
        let released = Released()
        try await finishImmediately(released)
        let deadline = ContinuousClock.now + .seconds(2)
        while !released.flag.withLock({ $0 }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(released.flag.withLock { $0 })
    }

    private func finishImmediately(_ released: Released) async throws {
        let capture = Capture(released)
        let value = try await ReplyGate<Int>.wait(
            cancellation: .readOnly, timeout: .seconds(30), onTimeout: { capture.timedOut() },
            send: { $0.resolve(.success(42)) })
        #expect(value == 42)
    }

    @Test func aFailureReplyIsThrown() async {
        await #expect(throws: JerdError.unavailable("No helper status was returned.")) {
            try await ReplyGate<Int>.wait(cancellation: .readOnly, timeout: nil) {
                $0.resolve(.failure(JerdError.unavailable("No helper status was returned.")))
            }
        }
    }
}
