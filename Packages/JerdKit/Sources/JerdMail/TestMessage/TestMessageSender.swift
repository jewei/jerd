import Foundation
import JerdFoundation
import JerdProcess

/// Sends the test email through the owned local SMTP service, the same way that an application
/// sends mail. It never uses the Mailpit send API, and no relay is configured.
struct TestMessageSender: Sendable {
    /// The limit of one send.
    static let timeout: Duration = .seconds(7)
    /// The end of the `curl` output that a failure message keeps.
    static let detailLimit = 2_048

    let commands: any CommandRunning
    let layout: MailLayout

    /// Writes the message to a private `test-<UUID>.eml` file, sends it with `curl`, and removes
    /// the file on every exit path.
    /// - Throws: `.processFailed` with the end of the `curl` output when the send fails.
    func send(_ message: TestMessage, smtpPort: UInt16) async throws {
        let file = layout.testMessageFile(UUID())
        // The file holds only the fixed test text, so a failed removal leaks nothing.
        defer { try? AtomicFile.remove(file) }
        try AtomicFile.write(message.data, to: file, durability: .standard)
        let result = try await commands.run(
            Self.request(file: file, smtpPort: smtpPort, in: layout.root), timeout: Self.timeout)
        guard result.succeeded else {
            throw JerdError.processFailed(
                "\(MailMessages.testFailed) \(result.diagnosticOutput.suffix(Self.detailLimit))")
        }
    }

    /// `curl` uploads the file to the local SMTP service, without a proxy.
    static func request(file: URL, smtpPort: UInt16, in folder: URL) -> ProcessRequest {
        ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/curl"),
            arguments: [
                "--silent", "--show-error", "--max-time", "5", "--noproxy", "*",
                "--url", "smtp://127.0.0.1:\(smtpPort)",
                "--mail-from", TestMessage.sender, "--mail-rcpt", TestMessage.recipient,
                "--upload-file", file.path,
            ], workingDirectory: folder)
    }
}
