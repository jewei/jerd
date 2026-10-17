import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import Testing

@Suite struct LoopbackSocketTests {
    @Test func anOccupiedLoopbackPortFailsTheBindCheckAndAcceptsConnections() throws {
        let listener = try LoopbackListener()
        let message = "Loopback port \(listener.port) is occupied or cannot be bound. No process was stopped."
        #expect(throws: JerdError.unavailable(message)) { try LoopbackProbe.system.requireBindable(listener.port) }
        #expect(LoopbackProbe.system.isAccepting(listener.port))
    }

    /// The bound socket does not listen, and it keeps the port reserved, so no parallel test can
    /// start a listener on it between the check and the connection.
    @Test func aBoundPortWithoutAListenerRefusesConnections() throws {
        let reserved = try LoopbackListener(listening: false)
        #expect(!LoopbackProbe.system.isAccepting(reserved.port))
    }

    /// A parallel test can take a found port before the bind check. A real defect fails every
    /// attempt; such a race fails only one.
    @Test func aFreePortPassesTheBindCheck() throws {
        var failures: [String] = []
        for _ in 0..<5 {
            let port = try UnusedLoopbackPort.find()
            do {
                try LoopbackProbe.system.requireBindable(port)
                return
            } catch {
                failures.append("\(port): \(error)")
            }
        }
        Issue.record("No free port passed the bind check: \(failures.joined(separator: "; "))")
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
