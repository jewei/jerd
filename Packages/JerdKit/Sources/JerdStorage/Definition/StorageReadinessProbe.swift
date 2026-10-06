import Foundation
import JerdServiceKit

/// The readiness rule of RustFS: a signed `ListBuckets` must pass, and then the console page
/// must answer with a 2xx status. Both requests run in this process, so a waiting start spawns
/// no process.
///
/// The instance then requires that RustFS owns exactly its two loopback listeners and no UDP
/// socket. The listed names are kept for the Storage page.
struct StorageReadinessProbe: Sendable {
    static let deadline: Duration = .seconds(45)
    static let interval: Duration = .milliseconds(150)

    let client: S3Client
    let consoleURL: URL
    let listed: ListedBuckets

    /// The readiness check of one launch. A timeout shows the end of the server log.
    var check: ReadinessCheck {
        let probe = self
        return ReadinessCheck(
            deadline: Self.deadline, interval: Self.interval, initialFailure: StorageMessages.noResponse,
            timeoutMessage: StorageMessages.readinessTimedOut, timeoutDetail: .logTail,
            probe: { try await probe.run() })
    }

    /// One round: the bucket list first, the console only after it passes.
    func run() async throws -> ReadinessCheck.ProbeResult {
        let names = try await client.listBuckets()
        let console = try await client.sender.send(URLRequest(url: consoleURL))
        guard console.succeeded else { return .notReady("The RustFS console answered HTTP \(console.status).") }
        listed.replace(with: names)
        return .ready
    }
}
