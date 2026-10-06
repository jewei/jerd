import Foundation

/// Asks a running Mailpit for its readiness answers. The live type is `MailServerProbe`.
public protocol MailServerProbing: Sendable {
    /// The body of `GET http://127.0.0.1:<webPort>/api/v1/info`.
    /// - Throws: when the server does not answer with a 2xx status.
    func information(webPort: UInt16) async throws -> Data

    /// The reply of the SMTP service to `NOOP`, for example `250 2.0.0 Ok`.
    /// - Throws: when the SMTP exchange fails.
    func smtpReply(smtpPort: UInt16) async throws -> String
}
