import JerdFoundation
import JerdProcess

/// Polls a readiness probe until it passes, the process exits, or the deadline passes.
public struct ReadinessPoller: Sendable {
    /// The longest probe failure text that a timeout message keeps.
    public static let failureLimit = 1_024

    private let clock: any TimeKeeping

    public init(clock: any TimeKeeping = SystemTimeKeeper()) { self.clock = clock }

    /// Each round first requires a live process, then runs one probe, then waits `check.interval`.
    ///
    /// The last failure is redacted with `secrets` before it is shortened, so a secret that
    /// crosses the cut cannot leave a fragment.
    /// - Throws: only `CancellationError`.
    public func poll(
        _ check: ReadinessCheck, secrets: [String] = [], isAlive: @Sendable () async -> Bool
    ) async throws -> ReadinessOutcome {
        let deadline = clock.now() + check.deadline
        var lastFailure = check.initialFailure
        while clock.now() < deadline {
            try Task.checkCancellation()
            guard await isAlive() else { return .exited }
            do {
                switch try await check.probe() {
                case .ready: return .ready
                case .notReady(let reason): lastFailure = reason
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastFailure = FailureDetail.describe(error)
            }
            try await clock.sleep(for: check.interval)
        }
        let redacted = LogRedactor.redact(lastFailure, values: secrets)
        return .timedOut(lastFailure: String(redacted.suffix(Self.failureLimit)))
    }
}
