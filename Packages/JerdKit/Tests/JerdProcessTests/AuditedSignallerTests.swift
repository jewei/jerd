import Darwin
import Foundation
import JerdFoundation
import Testing

@testable import JerdProcess

@Suite struct AuditedSignallerTests {
    private let refusal = JerdError.unavailable("Process ownership cannot be verified. No process was signalled.")

    private func signaller(
        result: Int32 = 0, match: ProcessIdentity.Match = .running, sent: SentSignals
    )
        -> AuditedSignaller
    {
        AuditedSignaller(
            send: { _, signal in
                sent.record(signal)
                return result
            }, match: { _ in match })
    }

    @Test(arguments: [SIGKILL, SIGUSR1, SIGHUP])
    func onlyGracefulSignalsAreAllowed(_ signal: Int32) {
        let sent = SentSignals()
        #expect(throws: refusal) { try signaller(sent: sent).signal(IdentityFactory.make(), with: signal) }
        #expect(sent.values.isEmpty)
    }

    @Test func thisProcessAnotherUserAndAMissingTokenAreRefused() {
        let sent = SentSignals()
        let unsafe = [
            IdentityFactory.make(pid: getpid()), IdentityFactory.make(user: geteuid() + 1),
            IdentityFactory.make(audit: nil), IdentityFactory.make(audit: [1, 2, 3]),
        ]
        for identity in unsafe {
            #expect(throws: refusal) { try signaller(sent: sent).signal(identity, with: SIGTERM) }
        }
        #expect(sent.values.isEmpty)
    }

    @Test(arguments: [ProcessIdentity.Match.exited, .replaced, .unknown])
    func aProcessThatIsNotVerifiedRunningIsRefused(_ match: ProcessIdentity.Match) {
        let sent = SentSignals()
        #expect(throws: refusal) {
            try signaller(match: match, sent: sent).signal(IdentityFactory.make(), with: SIGINT)
        }
        #expect(sent.values.isEmpty)
    }

    @Test func missingSystemSupportNeverFallsBackToAPIDSignal() {
        let unsupported = AuditedSignaller(send: nil, match: { _ in .running })
        #expect(!unsupported.isSupported)
        #expect(
            throws: JerdError.unavailable(
                "This macOS version cannot safely signal a saved process. Stop the verified service manually.")
        ) {
            try unsupported.signal(IdentityFactory.make(), with: SIGTERM)
        }
    }

    @Test func aVanishedTargetIsSuccessAndAnotherErrorIsReported() throws {
        let sent = SentSignals()
        try signaller(result: ESRCH, sent: sent).signal(IdentityFactory.make(), with: SIGQUIT)
        #expect(sent.values == [SIGQUIT])
        #expect(
            throws: JerdError.processFailed("The saved process could not stop safely (1). Its record was preserved.")
        ) {
            try signaller(result: EPERM, sent: sent).signal(IdentityFactory.make(), with: SIGTERM)
        }
    }

    @Test(.enabled(if: AuditedSignaller.system.isSupported))
    func theSystemSignallerStopsAVerifiedChild() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let sleeper = try await Fixtures.shared.executable("sleeper")
        let token = try await supervisor.start(
            ProcessRequest(executable: sleeper, workingDirectory: folder.url),
            log: ProcessLogFile(url: folder.path("s.log")))
        let pid = try #require(await waitForPID(in: folder.path("sleeper.pid")))
        try AuditedSignaller.system.signal(try ProcessIdentity.capture(pid), with: SIGTERM)
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(5)) == .signalled(signal: SIGTERM))
        #expect(await supervisor.stop(token, policy: .graceful()) == .stopped)
    }

    /// Regression test: libproc can return -1 and set `errno`.
    @Test func aMinusOneResultIsReadFromErrno() {
        #expect(AuditedSignaller.errorNumber(returned: -1, errno: ESRCH) == ESRCH)
        #expect(AuditedSignaller.errorNumber(returned: 0, errno: EPERM) == 0)
        #expect(AuditedSignaller.errorNumber(returned: EPERM, errno: 0) == EPERM)
    }
}
