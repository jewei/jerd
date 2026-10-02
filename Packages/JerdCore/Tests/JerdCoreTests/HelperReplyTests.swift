import Foundation
import Testing
@testable import JerdCore

struct HelperReplyTests {
    @Test func cancelledStatusFinishesPromptlyAndIgnoresLateReplies() async throws {
        let (replies, sent) = AsyncStream<HelperReply<Int>>.makeStream()
        let timeouts = ReplyTimeouts()
        let task = Task {
            try await HelperReply<Int>.wait(cancellation: .readOnly, timeout: .seconds(1),
                onTimeout: { await timeouts.record() }) { reply in
                sent.yield(reply); sent.finish()
            }
        }
        let reply = try #require(await replies.first { _ in true })
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - start < .milliseconds(500))
        #expect(!reply.resolve(.success(42)))
        #expect(!reply.resolve(.failure(JerdError.unavailable("late failure"))))
        #expect(await timeouts.count == 0)
    }

    @Test func cancellationBeforeRegistrationDoesNotSendStatus() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await HelperReply<Int>.wait(cancellation: .readOnly) { reply in
                Issue.record("A cancelled status request was sent.")
                reply.resolve(.success(42))
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(arguments: [false, true])
    func mutatingRequestWaitsForItsReplyDespiteCancellation(cancelBeforeSend: Bool) async throws {
        let (replies, sent) = AsyncStream<HelperReply<Int>>.makeStream()
        let task = Task {
            if cancelBeforeSend { withUnsafeCurrentTask { $0?.cancel() } }
            return try await HelperReply<Int>.wait(cancellation: .awaitReply, timeout: nil) { reply in
                sent.yield(reply); sent.finish()
            }
        }
        let reply = try #require(await replies.first { _ in true })
        task.cancel()
        #expect(reply.resolve(.success(42)))
        #expect(try await task.value == 42)
        #expect(!reply.resolve(.success(43)))
    }

    @Test func timeoutReportsFailureOnceAndImmediateRepliesFinishNormally() async throws {
        let timeouts = ReplyTimeouts()
        await #expect(throws: (any Error).self) {
            try await HelperReply<Int>.wait(cancellation: .readOnly, timeout: .milliseconds(20),
                onTimeout: { await timeouts.record() }) { _ in }
        }
        // The hook runs after resuming the caller. Wait for it independently.
        let deadline = ContinuousClock.now + .seconds(1)
        while await timeouts.count == 0, ContinuousClock.now < deadline { await Task.yield() }
        #expect(await timeouts.count == 1)
        let value = try await HelperReply<Int>.wait(cancellation: .awaitReply, timeout: .milliseconds(20),
            onTimeout: { await timeouts.record() }) { $0.resolve(.success(42)) }
        #expect(value == 42)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await timeouts.count == 1)
    }

    @Test func completionReleasesTheWatchdogBeforeItsDeadline() async throws {
        let state = WatchdogLifetimeState()
        try await finishImmediately(state)
        let deadline = ContinuousClock.now + .seconds(1)
        while !state.released, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(state.released)
    }

    private func finishImmediately(_ state: WatchdogLifetimeState) async throws {
        let capture = WatchdogCapture(state: state)
        let value = try await HelperReply<Int>.wait(cancellation: .readOnly, timeout: .seconds(30),
            onTimeout: { capture.timedOut() }) { $0.resolve(.success(42)) }
        #expect(value == 42)
    }
}

private actor ReplyTimeouts {
    var count = 0
    func record() { count += 1 }
}

private final class WatchdogLifetimeState: @unchecked Sendable {
    private let lock = NSLock()
    private var didRelease = false
    var released: Bool { lock.withLock { didRelease } }
    func recordRelease() { lock.withLock { didRelease = true } }
}

private final class WatchdogCapture: Sendable {
    let state: WatchdogLifetimeState
    init(state: WatchdogLifetimeState) { self.state = state }
    func timedOut() { Issue.record("A completed request reached its timeout hook.") }
    deinit { state.recordRelease() }
}
