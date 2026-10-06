import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct FastCGIPingTests {
    @Test func aCorrectAnswerPasses() async throws {
        let server = try FakeFPMServer(.bytes(FakeFPMServer.response()))
        defer { server.stop() }
        try await FastCGIPing().ping(socket: server.socket)
    }

    @Test func aSilentServerTimesOut() async throws {
        let server = try FakeFPMServer(.silent)
        defer { server.stop() }
        let started = ContinuousClock.now
        await #expect(throws: JerdError.processFailed("FPM did not answer its readiness request in time.")) {
            try await FastCGIPing(timeout: .milliseconds(150)).ping(socket: server.socket)
        }
        #expect(ContinuousClock.now - started < .seconds(2))
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

    /// Review web-r1 L4: a waiting ping holds no thread of the cooperative pool. Twice as many
    /// silent pings as the pool has threads must still let another task run at once.
    @Test func waitingPingsLeaveTheCooperativePoolFree() async throws {
        let server = try FakeFPMServer(.silent)
        defer { server.stop() }
        let count = ProcessInfo.processInfo.activeProcessorCount * 2
        let pings = Task {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<count {
                    group.addTask { _ = try? await FastCGIPing(timeout: .seconds(4)).ping(socket: server.socket) }
                }
            }
        }
        let started = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(200))
        let answer = await Task.detached { 6 * 7 }.value
        let elapsed = ContinuousClock.now - started
        pings.cancel()
        await pings.value
        #expect(answer == 42)
        #expect(elapsed < .seconds(2), "Another task waited \(elapsed) for a thread.")
    }

    @Test func cancellationStopsTheWait() async throws {
        let server = try FakeFPMServer(.silent)
        defer { server.stop() }
        let ping = Task { try await FastCGIPing(timeout: .seconds(30)).ping(socket: server.socket) }
        try await Task.sleep(for: .milliseconds(50))
        ping.cancel()
        let started = ContinuousClock.now
        await #expect(throws: CancellationError.self) { try await ping.value }
        #expect(ContinuousClock.now - started < .seconds(2))
    }
}
