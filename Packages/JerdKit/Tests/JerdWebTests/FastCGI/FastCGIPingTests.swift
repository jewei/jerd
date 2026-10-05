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
