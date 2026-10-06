import Foundation
import JerdFoundation
import JerdMail
import os

/// Scripted readiness answers of Mailpit. By default it reports the given version and database
/// and accepts `NOOP`.
final class FakeMailServer: MailServerProbing {
    struct Script {
        var version = "v1.31.3"
        var database: String?
        var informationError: JerdError?
        var smtpReply = "250 2.0.0 Ok\r\n"
    }

    private let script = OSAllocatedUnfairLock(initialState: Script())
    private let counts = OSAllocatedUnfairLock(initialState: (information: 0, smtp: 0))

    /// The number of information requests and SMTP checks so far.
    var informationCalls: Int { counts.withLock { $0.information } }
    var smtpCalls: Int { counts.withLock { $0.smtp } }

    func update(_ change: @Sendable (inout Script) -> Void) { script.withLock { change(&$0) } }

    /// Reports `database` as the open database from now on.
    func serve(database: URL) { update { $0.database = database.path } }

    func information(webPort: UInt16) async throws -> Data {
        counts.withLock { $0.information += 1 }
        let current = script.withLock { $0 }
        if let error = current.informationError { throw error }
        let object: [String: Any] = [
            "Version": current.version, "Database": current.database ?? "/missing", "Messages": 0,
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    func smtpReply(smtpPort: UInt16) async throws -> String {
        counts.withLock { $0.smtp += 1 }
        return script.withLock { $0.smtpReply }
    }
}
