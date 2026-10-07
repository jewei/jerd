import Foundation

/// The plain-text test email, with CRLF line ends as SMTP requires.
struct TestMessage: Equatable, Sendable {
    static let sender = "hello@jerd.test"
    static let recipient = "inbox@jerd.test"

    /// The ID in `Message-ID: <ID@jerd.test>`.
    let id: UUID

    init(id: UUID = UUID()) { self.id = id }

    /// The exact message bytes.
    var data: Data { Data(text.utf8) }

    /// The message text. The last line also ends with CRLF.
    var text: String {
        [
            "From: Jerd <\(Self.sender)>",
            "To: Local Inbox <\(Self.recipient)>",
            "Subject: Jerd mail test",
            "Message-ID: <\(id.uuidString)@jerd.test>",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "",
            "Jerd captured this message through its local SMTP service.",
            "Open the inbox to inspect messages from your applications.",
            "",
        ].joined(separator: "\r\n")
    }
}
