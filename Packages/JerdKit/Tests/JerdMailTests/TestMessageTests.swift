import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdMail

@Suite struct TestMessageTests {
    @Test func theMessageTextIsExactWithCRLFLineEnds() throws {
        let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let expected =
            "From: Jerd <hello@jerd.test>\r\nTo: Local Inbox <inbox@jerd.test>\r\nSubject: Jerd mail test\r\n"
            + "Message-ID: <6F9619FF-8B86-D011-B42D-00C04FC964FF@jerd.test>\r\nMIME-Version: 1.0\r\n"
            + "Content-Type: text/plain; charset=UTF-8\r\n\r\n"
            + "Jerd captured this message through its local SMTP service.\r\n"
            + "Open the inbox to inspect messages from your applications.\r\n"
        #expect(TestMessage(id: id).text == expected)
        #expect(TestMessage(id: id).data == Data(expected.utf8))
    }

    @Test func theSenderUploadsAPrivateFileThroughLocalSMTPAndRemovesIt() async throws {
        let harness = try MailHarness()
        try OwnedDirectory.create(harness.mail.root)
        let sender = TestMessageSender(commands: harness.commands, layout: harness.mail)
        let message = TestMessage()
        try await sender.send(message, smtpPort: 2_525)
        let request = try #require(harness.commands.requests(named: "curl").first)
        let file = try #require(request.arguments.last)
        #expect(
            Array(request.arguments.dropLast())
                == [
                    "--silent", "--show-error", "--max-time", "5", "--noproxy", "*", "--url", "smtp://127.0.0.1:2525",
                    "--mail-from", "hello@jerd.test", "--mail-rcpt", "inbox@jerd.test", "--upload-file",
                ])
        #expect(file.hasPrefix(harness.mail.root.path + "/test-") && file.hasSuffix(".eml"))
        #expect(harness.uploaded?.data == message.data)
        #expect(harness.uploaded?.mode == 0o600)
        #expect(!exists(URL(fileURLWithPath: file)))
    }

    @Test func aFailedSendShowsTheEndOfTheCurlOutputAndRemovesTheFile() async throws {
        let harness = try MailHarness()
        try OwnedDirectory.create(harness.mail.root)
        let detail = String(repeating: "x", count: 3_000) + "curl: (7) Failed to connect"
        harness.update { $0.sendResult = CommandResult(status: 7, output: detail) }
        let sender = TestMessageSender(commands: harness.commands, layout: harness.mail)
        await #expect(throws: JerdError.processFailed("The test email could not be sent: \(detail.suffix(2_048))")) {
            try await sender.send(TestMessage(), smtpPort: 2_525)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: harness.mail.root.path)
        #expect(!names.contains { $0.hasSuffix(".eml") })
    }
}
