import Foundation
import JerdServiceKit

/// The readiness rule of RustFS: a signed `ListBuckets` must pass, and then the console page
/// must answer with a 2xx status. Both requests run in this process, so a waiting start spawns
/// no process.
///
/// The instance then requires that RustFS owns exactly its two loopback listeners and no UDP
/// socket. The listed names are kept for the Storage page, in the launch that the probe checks.
struct StorageReadinessProbe: Sendable {
    static let deadline: Duration = .seconds(45)
    static let interval: Duration = .milliseconds(150)
    /// The limit of one console request, so that a hung console cannot hold a round.
    static let consoleTimeout: TimeInterval = 3

    let client: S3Client
    /// The transport of the console request. It does not depend on the inner parts of `client`.
    let console: any S3Sending
    let consoleURL: URL
    let launch: StorageLaunch
    let launchID: UUID

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
        let answer = try await console.send(consoleRequest)
        guard answer.succeeded else { return .notReady("The RustFS console answered HTTP \(answer.status).") }
        launch.replaceNames(names, of: launchID)
        return .ready
    }

    /// `GET` of the console page, without a cache, within `consoleTimeout`.
    var consoleRequest: URLRequest {
        URLRequest(url: consoleURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.consoleTimeout)
    }
}
