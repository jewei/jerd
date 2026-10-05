import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct LoopbackSocketTests {
    @Test func anOccupiedLoopbackPortFailsTheBindCheckAndAcceptsConnections() throws {
        let listener = try LoopbackListener()
        let message = "Loopback port \(listener.port) is occupied or cannot be bound. No process was stopped."
        #expect(throws: JerdError.unavailable(message)) { try LoopbackProbe.system.requireBindable(listener.port) }
        #expect(LoopbackProbe.system.isAccepting(listener.port))
    }

    @Test func aClosedPortPassesTheBindCheckAndRefusesConnections() throws {
        let port = try {
            let listener = try LoopbackListener()
            return listener.port
        }()
        try LoopbackProbe.system.requireBindable(port)
        #expect(!LoopbackProbe.system.isAccepting(port))
    }

    @Test func theRealInspectionSeesAChildListenerAndVerifiesItsOwnership() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let binary = try await Fixtures.shared.executable("loopback-listener")
        let token = try await supervisor.start(
            ProcessRequest(executable: binary, arguments: ["udp"], workingDirectory: folder.url),
            log: ProcessLogFile(url: folder.path("listener.log")))
        #expect(await eventually { UInt16(text(folder.path("listener.log")).trimmingCharacters(in: .newlines)) != nil })
        let port = try #require(UInt16(text(folder.path("listener.log")).trimmingCharacters(in: .newlines)))
        let pid = try #require(await supervisor.processID(of: token))
        let guardian = LoopbackPortGuard()
        await #expect(throws: JerdError.unavailable("Local port \(port) is occupied. No process was stopped.")) {
            try await guardian.requireFree(port)
        }
        await #expect(throws: JerdError.processFailed("The service opened an unexpected UDP socket.")) {
            try await guardian.verifyOwnership(pid: pid, expected: [port])
        }
        try await guardian.verifyOwnership(pid: pid, expected: [port], allowUDP: true)
        #expect(await supervisor.stop(token, policy: .forceful()) == .stopped)
    }
}
