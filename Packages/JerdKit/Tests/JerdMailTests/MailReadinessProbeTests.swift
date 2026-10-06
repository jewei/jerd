import Foundation
import JerdFoundation
import JerdServiceKit
import Testing

@testable import JerdMail

@Suite struct MailReadinessProbeTests {
    static let database = URL(fileURLWithPath: "/Users/me/Library/Application Support/Jerd/mail/inbox/messages.sqlite")

    static func probe(_ server: FakeMailServer) -> MailReadinessProbe {
        MailReadinessProbe(
            runtime: MailSettingsTests.runtime, database: database, ports: MailPorts(smtp: 1_026, web: 8_026),
            server: server)
    }

    static func body(version: String, database: String) -> Data {
        Data("{\"Version\":\"\(version)\",\"Database\":\"\(database)\",\"Messages\":3}".utf8)
    }

    @Test func theInformationMustNameTheSavedVersionAndTheInboxDatabase() {
        let probe = Self.probe(FakeMailServer())
        let path = Self.database.path
        #expect(probe.evaluate(information: Self.body(version: "v1.31.3", database: path)) == .ready)
        let equivalent = "/Users/me/Library/Application Support/Jerd/mail/./inbox/messages.sqlite"
        #expect(probe.evaluate(information: Self.body(version: "v1.31.3", database: equivalent)) == .ready)
        for body in [
            Self.body(version: "1.31.3", database: path), Self.body(version: "v1.31.4", database: path),
            Self.body(version: "v1.31.3", database: "/tmp/messages.sqlite"), Data("not json".utf8),
            Data("{\"Version\":\"v1.31.3\"}".utf8),
        ] {
            #expect(probe.evaluate(information: body) != .ready)
        }
    }

    @Test(arguments: [("250 2.0.0 Ok\r\n", true), ("250-first\r\n", false), ("550 no\r\n", false), ("", false)])
    func theSMTPReplyMustStartWith250AndASpace(_ reply: String, _ ready: Bool) {
        #expect((MailReadinessProbe.evaluate(smtpReply: reply) == .ready) == ready)
    }

    @Test func theSMTPCheckRunsOnlyAfterTheInformationPasses() async throws {
        let server = FakeMailServer()
        server.update { $0.informationError = JerdError.unavailable("Connection refused.") }
        let probe = Self.probe(server)
        await #expect(throws: JerdError.unavailable("Connection refused.")) { try await probe.run() }
        server.update { $0.informationError = nil }
        server.update { $0.database = "/tmp/other.sqlite" }
        #expect(try await probe.run() == .notReady("Mailpit opened a different database."))
        #expect(server.smtpCalls == 0)
        server.serve(database: Self.database)
        #expect(try await probe.run() == .ready)
        #expect(server.smtpCalls == 1)
    }

    @Test func theCheckWaitsTwentySecondsAndShowsTheLogTail() {
        let check = Self.probe(FakeMailServer()).check
        #expect(check.deadline == .seconds(20))
        #expect(check.interval == .milliseconds(100))
        #expect(check.timeoutDetail == .logTail)
        #expect(check.timeoutMessage == "Mailpit did not pass its SMTP and web checks.")
    }
}
