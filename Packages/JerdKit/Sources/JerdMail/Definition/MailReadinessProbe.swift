import Foundation
import JerdFoundation
import JerdServiceKit

/// The readiness rule of Mailpit: the information API must name the saved version and the inbox
/// database, and then the SMTP service must answer `NOOP` with `250 `.
///
/// The instance then requires that Mailpit owns exactly its two loopback listeners and no UDP
/// socket. The probe itself spawns nothing until the web service answers.
struct MailReadinessProbe: Sendable {
    static let deadline: Duration = .seconds(20)
    static let interval: Duration = .milliseconds(100)

    /// The two fields of `/api/v1/info` that the rule reads.
    struct Information: Decodable, Equatable {
        let version: String
        let database: String

        private enum CodingKeys: String, CodingKey {
            case version = "Version"
            case database = "Database"
        }
    }

    let runtime: MailRuntime
    let database: URL
    let ports: MailPorts
    let server: any MailServerProbing

    /// The readiness check of one launch. A timeout shows the end of the server log.
    var check: ReadinessCheck {
        let probe = self
        return ReadinessCheck(
            deadline: Self.deadline, interval: Self.interval, initialFailure: MailMessages.noResponse,
            timeoutMessage: MailMessages.readinessTimedOut, timeoutDetail: .logTail, probe: { try await probe.run() })
    }

    /// One round: the information request first, the SMTP check only after it passes.
    func run() async throws -> ReadinessCheck.ProbeResult {
        let information = try await server.information(webPort: ports.web)
        if case .notReady(let reason) = evaluate(information: information) { return .notReady(reason) }
        return Self.evaluate(smtpReply: try await server.smtpReply(smtpPort: ports.smtp))
    }

    /// `Version` must be `v<version>` and `Database` must be the inbox database file.
    func evaluate(information body: Data) -> ReadinessCheck.ProbeResult {
        guard let information = try? JSONDecoder().decode(Information.self, from: body) else {
            return .notReady("Mailpit returned an unexpected information answer.")
        }
        guard information.version == "v\(runtime.version)" else {
            return .notReady("Mailpit reported version \(information.version).")
        }
        let reported = URL(fileURLWithPath: information.database).standardizedFileURL
        guard reported == database.standardizedFileURL else {
            return .notReady("Mailpit opened a different database.")
        }
        return .ready
    }

    /// The SMTP service is ready when its reply starts with `250 `.
    static func evaluate(smtpReply: String) -> ReadinessCheck.ProbeResult {
        smtpReply.hasPrefix("250 ") ? .ready : .notReady("The SMTP service did not accept NOOP.")
    }
}
