import JerdFoundation
import JerdProcess

/// Runs the version command of a runtime binary and requires the registered version.
public struct VersionProbe: Sendable {
    /// The default limit of one version command.
    public static let defaultTimeout: Duration = .seconds(10)

    public var request: ProcessRequest
    public var rule: VersionRule
    /// The `.unavailable` message when the output does not satisfy the rule.
    public var mismatchMessage: String
    public var timeout: Duration

    public init(
        request: ProcessRequest, rule: VersionRule, mismatchMessage: String, timeout: Duration = defaultTimeout
    ) {
        self.request = request
        self.rule = rule
        self.mismatchMessage = mismatchMessage
        self.timeout = timeout
    }

    /// Runs the command. A non-zero status or output that fails the rule is a mismatch.
    /// - Throws: `.unavailable(mismatchMessage)`, or the error of the command itself.
    public func verify(using commands: any CommandRunning) async throws {
        let result = try await commands.run(request, timeout: timeout)
        guard result.succeeded, rule.matches(result.output) else {
            throw JerdError.unavailable(mismatchMessage)
        }
    }
}
