import Darwin
import Foundation
import JerdFoundation
import JerdServiceKit
import Testing

@testable import JerdMail

/// An opt-in test with a real Mailpit 1.31.3 runtime. It uses a temporary data folder and free
/// loopback ports only.
@Suite(.serialized) struct MailIntegrationTests {
    static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["JERD_MAIL_INTEGRATION"] == "1" && environment["JERD_MAIL_RUNTIME"] != nil))
    func smtpCapturesMIMEAndKeepsMessagesAcrossRestartsAndUpdates() async throws {
        let folder = URL(fileURLWithPath: try #require(Self.environment["JERD_MAIL_RUNTIME"]))
        let run = try await MailIntegrationRun(runtime: folder)
        do {
            try await run.manager.start()
            try await checkInformationAndHostAllowlist(run)
            let id = try await captureMIMEWithAnAttachment(run)
            try await captureAPlainMessageAndATestEmail(run)
            try await keepMessagesAcrossAPortChange(run, id: id)
            try await updateAndRollBack(run)
            try await detectAnExternalStop(run)
            try await refuseAMissingDatabaseAndAnotherIdentity(run)
            run.directory.remove()
        } catch {
            do {
                try await run.manager.stop()
                run.directory.remove()
            } catch {
                Issue.record("Mail test data was kept in \(run.directory.url.path) because cleanup failed.")
            }
            throw error
        }
    }

    private func checkInformationAndHostAllowlist(_ run: MailIntegrationRun) async throws {
        let snapshot = await run.manager.snapshot()
        #expect(snapshot.state.processID != nil && !snapshot.state.isBusy)
        let info = try await run.object("api/v1/info")
        #expect(info["Version"] as? String == "v1.31.3")
        #expect(info["LatestVersion"] as? String == "disabled")
        #expect(info["Messages"] as? Int == 0)
        let rejected = try await run.get(
            "api/v1/info", ["--header", "Host: untrusted.example.test", "--write-out", "%{http_code}"])
        #expect(rejected.output.hasSuffix("403"))
        #expect(mode(run.mail.inboxDatabaseFile) == 0o600)
        await #expect(throws: MailMessages.stopBeforeEditing) {
            try await run.manager.edit(ports: try MailIntegrationRun.freePorts())
        }
    }

    private func captureMIMEWithAnAttachment(_ run: MailIntegrationRun) async throws -> String {
        let subject = "Jerd mail: café"
        let attachment = "Jerd attachment\n"
        let mime = [
            "From: Sender <hello@jerd.test>", "To: Receiver <inbox@jerd.test>",
            "Subject: =?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?=",
            "Message-ID: <\(UUID().uuidString)@jerd.test>", "MIME-Version: 1.0",
            "Content-Type: multipart/mixed; boundary=jerd-mixed", "", "--jerd-mixed",
            "Content-Type: multipart/alternative; boundary=jerd-body", "", "--jerd-body",
            "Content-Type: text/plain; charset=UTF-8", "", "Plain café body.", "--jerd-body",
            "Content-Type: text/html; charset=UTF-8", "", "<p>HTML café body.</p>", "--jerd-body--", "--jerd-mixed",
            "Content-Type: text/plain; name=report.txt", "Content-Disposition: attachment; filename=report.txt",
            "Content-Transfer-Encoding: base64", "", Data(attachment.utf8).base64EncodedString(), "--jerd-mixed--", "",
        ].joined(separator: "\r\n")
        try await run.send(mime, to: ["inbox@jerd.test"])
        let captured = try await run.object("api/v1/message/latest")
        #expect(captured["Subject"] as? String == subject)
        #expect((captured["Text"] as? String)?.contains("Plain café body.") == true)
        #expect((captured["HTML"] as? String)?.contains("<p>HTML café body.</p>") == true)
        let attachments = try #require(captured["Attachments"] as? [[String: Any]])
        let item = try #require(attachments.first)
        #expect(attachments.count == 1 && item["FileName"] as? String == "report.txt")
        let id = try #require(captured["ID"] as? String)
        let part = try #require(item["PartID"] as? String)
        #expect(try await run.get("api/v1/message/\(id)/part/\(part)").output == attachment)
        return id
    }

    private func captureAPlainMessageAndATestEmail(_ run: MailIntegrationRun) async throws {
        let plain = [
            "From: Sender <hello@jerd.test>", "To: First <first@jerd.test>, Second <second@jerd.test>",
            "Cc: Third <third@jerd.test>", "Subject: Plain message without generated headers", "",
            "Plain message body.", "",
        ].joined(separator: "\r\n")
        try await run.send(plain, to: ["first@jerd.test", "second@jerd.test", "third@jerd.test"])
        let captured = try await run.object("api/v1/message/latest")
        #expect((captured["Text"] as? String)?.contains("Plain message body.") == true)
        let to = try #require(captured["To"] as? [[String: Any]])
        #expect(to.compactMap { $0["Address"] as? String } == ["first@jerd.test", "second@jerd.test"])
        try await run.manager.sendTestEmail()
        let latest = try await run.object("api/v1/message/latest")
        #expect(latest["Subject"] as? String == "Jerd mail test")
        #expect(try await run.object("api/v1/info")["Messages"] as? Int == 3)
    }

    private func keepMessagesAcrossAPortChange(_ run: MailIntegrationRun, id: String) async throws {
        try await run.manager.stop()
        #expect(await run.manager.snapshot().state == .stopped)
        #expect(exists(run.mail.inboxDatabaseFile) && !exists(run.mail.activeRunFile))
        try await run.manager.edit(ports: try MailIntegrationRun.freePorts())
        try await run.manager.start()
        #expect(try await run.object("api/v1/message/\(id)")["Subject"] as? String == "Jerd mail: café")
        #expect(try await run.object("api/v1/info")["Messages"] as? Int == 3)
    }

    private func updateAndRollBack(_ run: MailIntegrationRun) async throws {
        let updated = MailRuntime(id: "mailpit-update-test", version: run.runtime.version, path: run.runtime.path)
        try await run.manager.updateRuntime(updated)
        #expect(await run.manager.snapshot().settings.runtime == updated)
        #expect(try await run.object("api/v1/info")["Messages"] as? Int == 3)
        let invalid = MailRuntime(id: "mailpit-invalid-update", version: "99.0.0", path: run.runtime.path)
        await #expect(throws: (any Error).self) { try await run.manager.updateRuntime(invalid) }
        let snapshot = await run.manager.snapshot()
        #expect(snapshot.settings.runtime == updated && snapshot.state.processID != nil)
        #expect(try await run.object("api/v1/info")["Messages"] as? Int == 3)
        let backups = try FileManager.default.contentsOfDirectory(atPath: run.mail.runtimeBackupsDirectory.path)
        #expect(backups.count == 2)
    }

    private func detectAnExternalStop(_ run: MailIntegrationRun) async throws {
        let pid = try #require(await run.manager.snapshot().processID)
        #expect(kill(pid, SIGTERM) == 0)
        #expect(await eventually(timeout: .seconds(10)) { await run.manager.snapshot().state.failure != nil })
        try await run.manager.start()
        try await run.manager.stop()
    }

    private func refuseAMissingDatabaseAndAnotherIdentity(_ run: MailIntegrationRun) async throws {
        let retained = run.directory.path("retained.sqlite")
        try FileManager.default.moveItem(at: run.mail.inboxDatabaseFile, to: retained)
        await #expect(throws: MailMessages.initializedMismatch) { try await run.manager.start() }
        #expect(!exists(run.mail.inboxDatabaseFile))
        try FileManager.default.moveItem(at: retained, to: run.mail.inboxDatabaseFile)
        let identity = try #require(contents(run.mail.runtimeIdentityFile))
        let other = MailRuntime(id: "other", version: "2.0", path: run.runtime.path)
        try MarkerFile.write(other, to: run.mail.runtimeIdentityFile)
        await #expect(throws: MailMessages.identityMismatch) { try await run.manager.start() }
        try AtomicFile.write(identity, to: run.mail.runtimeIdentityFile)
        try await run.manager.start()
        #expect(try await run.object("api/v1/info")["Messages"] as? Int == 3)
        try await run.manager.stop()
    }
}
