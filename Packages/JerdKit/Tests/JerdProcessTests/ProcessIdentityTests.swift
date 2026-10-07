import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import Testing

@Suite struct ProcessIdentityTests {
    @Test func aCaptureOfThisProcessIsCompleteAndStillRunning() throws {
        let identity = try ProcessIdentity.capture(getpid())
        #expect(identity.processID == getpid())
        #expect(identity.userID == geteuid())
        #expect(identity.executable.hasPrefix("/"))
        #expect(identity.auditWords?.count == 8)
        #expect(identity.bootSessionID?.isEmpty == false)
        #expect(identity.liveMatch() == .running)
    }

    @Test(arguments: [Int32(0), 1, Int32.max])
    func pidsThatCannotBeInspectedAreRefused(_ pid: Int32) {
        #expect(throws: JerdError.unavailable("The process is no longer available for inspection.")) {
            try ProcessIdentity.capture(pid)
        }
    }

    @Test func comparisonRules() {
        let saved = IdentityFactory.make()
        let table: [(ProcessIdentity, ProcessIdentity.Match)] = [
            (saved, .running),
            (IdentityFactory.make(user: saved.userID + 1), .replaced),
            (IdentityFactory.make(started: 101), .replaced),
            (IdentityFactory.make(micro: 6), .replaced),
            (IdentityFactory.make(session: "SESSION-B"), .replaced),
            (IdentityFactory.make(executable: "/bin/other"), .unknown),
            (IdentityFactory.make(audit: [1, 2, 3, 4, 5, 6, 7, 9]), .unknown),
            (IdentityFactory.make(audit: nil), .unknown),
        ]
        for (current, expected) in table { #expect(saved.compare(with: current) == expected) }
    }

    @Test func aClockChangeThatMovesTheBootTimeDoesNotReplaceALiveProcess() {
        let saved = IdentityFactory.make(boot: 1_000)
        #expect(saved.compare(with: IdentityFactory.make(boot: 1_007)) == .running)
        let legacy = IdentityFactory.make(boot: 1_000, session: nil)
        #expect(legacy.compare(with: IdentityFactory.make(boot: 990)) == .running)
    }

    @Test func anExitedChildIsExitedAsZombieAndAfterTheReap() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let sleeper = try await Fixtures.shared.executable("sleeper")
        let token = try await supervisor.start(
            ProcessRequest(executable: sleeper, workingDirectory: folder.url),
            log: ProcessLogFile(url: folder.path("s.log")))
        let pid = try #require(await waitForPID(in: folder.path("sleeper.pid")))
        let identity = try ProcessIdentity.capture(pid)
        #expect(identity.liveMatch() == .running)
        kill(pid, SIGKILL)
        _ = await supervisor.waitForExit(of: token, timeout: .seconds(5))
        #expect(identity.liveMatch() == .exited)
        #expect(await supervisor.stop(token, policy: .graceful()) == .stopped)
        #expect(identity.liveMatch() == .exited)
    }

    @Test func legacyJSONWithoutABootSessionDecodesAndNewJSONKeepsTheOldKeys() throws {
        let legacy = Data(
            "{\"auditWords\":[1,2,3,4,5,6,7,8],\"bootSeconds\":3,\"processID\":42,\"userID\":501,\"startedSeconds\":1,\"executable\":\"\\/bin\\/x\",\"startedMicroseconds\":2}"
                .utf8)
        let decoded = try JSONDecoder().decode(ProcessIdentity.self, from: legacy)
        #expect(decoded.bootSessionID == nil)
        #expect(decoded.executable == "/bin/x")
        let encoded =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(IdentityFactory.make())) as? [String: Any]
        let keys = Set(encoded?.keys.map { $0 } ?? [])
        #expect(
            keys == [
                "processID", "userID", "startedSeconds", "startedMicroseconds", "bootSeconds", "executable",
                "auditWords", "bootSessionID",
            ])
    }
}
