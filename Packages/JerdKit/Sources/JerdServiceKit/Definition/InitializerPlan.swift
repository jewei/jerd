import Foundation
import JerdProcess

/// A one-shot process of a first start that creates new data, for example `initdb`.
///
/// It runs as an owned process of the instance, like a server: with a run record, with the
/// instance lock held, and with the graceful stop policy. It must exit within `timeout`. A
/// timeout stops it gracefully; when that stop also times out, the process stays owned and the
/// instance is `stuck` with its lock and record.
public struct InitializerPlan: Sendable {
    public var request: ProcessRequest
    /// How long the process may run before it is stopped.
    public var timeout: Duration
    /// The first sentence of the timeout message, for example "Database initialization timed out."
    public var timeoutMessage: String
    /// Secrets that never appear in messages and in the returned output.
    public var secrets: [String]
    /// Private input files with a secret, for example a password file. They are removed when the
    /// wait for the exit ends. A failed removal fails the step.
    public var secretFiles: [URL]

    public init(
        request: ProcessRequest, timeout: Duration, timeoutMessage: String, secrets: [String] = [],
        secretFiles: [URL] = []
    ) {
        self.request = request
        self.timeout = timeout
        self.timeoutMessage = timeoutMessage
        self.secrets = secrets
        self.secretFiles = secretFiles
    }

    /// Removes the secret files of a plan that never runs, for example after a failed write of
    /// an input file.
    /// - Returns: `failure`, or a combined error when a secret file is still there.
    public func discard(after failure: any Error) -> any Error {
        launchPlan.discard(after: failure)
    }

    /// The plan of the owned process. An initializer has no readiness check and no listener:
    /// the instance waits for its exit instead, so the check is never polled.
    var launchPlan: LaunchPlan {
        let unused = ReadinessCheck(
            deadline: .zero, interval: .zero, initialFailure: timeoutMessage, timeoutMessage: timeoutMessage,
            timeoutDetail: .logTail, probe: { .notReady(timeoutMessage) })
        return LaunchPlan(request: request, ports: [], readiness: unused, secrets: secrets, secretFiles: secretFiles)
    }
}
