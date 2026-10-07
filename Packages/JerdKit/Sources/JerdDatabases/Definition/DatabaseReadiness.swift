import Foundation
import JerdProcess
import JerdServiceKit

/// The readiness rule of every engine: the client must print exactly `42` (SQL) or `PONG` (Redis).
enum DatabaseReadiness {
    static let deadline: Duration = .seconds(45)
    static let interval: Duration = .milliseconds(100)
    /// The limit of one client probe.
    static let probeTimeout: Duration = .seconds(2)

    /// A check that runs `client` and compares its trimmed output (standard output and error) with
    /// `reply`. A failure keeps the end of the client output with the password redacted.
    static func check(
        client: ProcessRequest, reply: String, password: String, commands: any CommandRunning
    )
        -> ReadinessCheck
    {
        ReadinessCheck(
            deadline: deadline, interval: interval, initialFailure: DatabaseMessages.noResponse,
            timeoutMessage: DatabaseMessages.readinessTimedOut, timeoutDetail: .lastFailure,
            probe: {
                let result = try await commands.run(client, timeout: probeTimeout)
                if result.succeeded, result.output.trimmingCharacters(in: .whitespacesAndNewlines) == reply {
                    return .ready
                }
                let redacted = LogRedactor.redact(result.diagnosticOutput, values: [password])
                return .notReady(String(redacted.suffix(ReadinessPoller.failureLimit)))
            })
    }
}
