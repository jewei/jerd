import Foundation
import JerdFoundation
import Testing
import os

@testable import JerdWeb

@Suite struct FastCGIPingTests {
    @Test func aCorrectAnswerPasses() async throws {
        let server = try FakeFPMServer(.bytes(FakeFPMServer.response()))
        defer { server.stop() }
        try await FastCGIPing().ping(socket: server.socket)
    }

    /// The error text proves that the deadline fired, because a silent server never answers.
    /// The lower bound proves that the ping waited. The loose upper bound catches a ping without a
    /// deadline, which would wait forever; a tight bound would only measure thread scheduling under load.
    @Test(.timeLimit(.minutes(1))) func aSilentServerTimesOut() async throws {
        let server = try FakeFPMServer(.silent)
        defer { server.stop() }
        let started = ContinuousClock.now
        await #expect(throws: JerdError.processFailed("FPM did not answer its readiness request in time.")) {
            try await FastCGIPing(timeout: .milliseconds(150)).ping(socket: server.socket)
        }
        let elapsed = ContinuousClock.now - started
        #expect(elapsed >= .milliseconds(150))
        #expect(elapsed < .seconds(10))
    }

    @Test func aClosedConnectionIsIncomplete() async throws {
        let server = try FakeFPMServer(.close)
        defer { server.stop() }
        await #expect(
            throws: JerdError.processFailed("FPM closed its readiness connection without a complete response.")
        ) { try await FastCGIPing(timeout: .seconds(2)).ping(socket: server.socket) }
    }

    @Test func aMissingSocketIsNotAccepted() async throws {
        await #expect(throws: JerdError.processFailed("FPM did not accept its readiness request.")) {
            try await FastCGIPing().ping(
                socket: URL(fileURLWithPath: "/tmp/jerd-missing-\(UUID().uuidString.prefix(8)).sock"))
        }
    }

    @Test func aLongPathIsInvalid() async {
        await #expect(throws: JerdError.invalid("The FPM probe path is invalid.")) {
            try await FastCGIPing().ping(socket: URL(fileURLWithPath: "/" + String(repeating: "p", count: 110)))
        }
    }

    /// A waiting ping holds no thread of the cooperative pool. Twice as many silent pings as the
    /// pool has threads all wait, and another task must still run before any ping ends.
    /// If pings held pool threads, the detached task could run only after a ping ended (after 60 s).
    @Test(.timeLimit(.minutes(1))) func waitingPingsLeaveTheCooperativePoolFree() async throws {
        let server = try FakeFPMServer(.silent)
        defer { server.stop() }
        let count = ProcessInfo.processInfo.activeProcessorCount * 2
        let finished = OSAllocatedUnfairLock(initialState: 0)
        let pings = Task {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        _ = try? await FastCGIPing(timeout: .seconds(60)).ping(socket: server.socket)
                        finished.withLock { $0 += 1 }
                    }
                }
            }
        }
        #expect(await waitUntil { server.accepted >= count })
        let answer = await Task.detached { 6 * 7 }.value
        let finishedPings = finished.withLock { $0 }
        pings.cancel()
        await pings.value
        #expect(answer == 42)
        #expect(finishedPings == 0, "\(finishedPings) pings ended before another task could run.")
    }

    /// The bound is loose because the resume waits for a pool thread under load. It is still far
    /// below the 30 s timeout, so only cancellation can end the wait in time.
    @Test(.timeLimit(.minutes(1))) func cancellationStopsTheWait() async throws {
        let server = try FakeFPMServer(.silent)
        defer { server.stop() }
        let ping = Task { try await FastCGIPing(timeout: .seconds(30)).ping(socket: server.socket) }
        #expect(await waitUntil { server.accepted >= 1 })
        ping.cancel()
        let started = ContinuousClock.now
        await #expect(throws: CancellationError.self) { try await ping.value }
        #expect(ContinuousClock.now - started < .seconds(10))
    }
}
