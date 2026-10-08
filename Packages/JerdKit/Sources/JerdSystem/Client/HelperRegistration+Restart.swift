import JerdFoundation

extension HelperRegistration {
    /// How long `reregister()` waits for the old helper to exit after `unregister()`.
    static let exitTimeLimit: Duration = .seconds(5)
    /// The time between two checks of the old helper.
    static let exitPollInterval: Duration = .milliseconds(100)
    /// The register attempts after a transient failure ("Operation not permitted").
    static let registerAttempts = 4
    /// The wait between two register attempts.
    static let registerRetryDelay: Duration = .milliseconds(500)
    /// The total of all waits in one `reregister()`: the exit wait and the retries share it. With
    /// the `SMAppService` calls, a restart thus ends in about this time; Quit waits longer.
    public static let restartWaitLimit: Duration = .seconds(8)

    /// Registers the daemon again, so launchd starts the helper file of this app. It changes no hosts
    /// or trust.
    ///
    /// `SMAppService.unregister()` returns when it stopped the old job, but the old process can
    /// still be exiting, and a `register()` then fails with "Operation not permitted" and leaves the
    /// login item off. So this waits until the daemon is no longer enabled and no helper process
    /// runs (at most `exitTimeLimit`), and retries a transient failure a few times. All waits
    /// together stay within `restartWaitLimit`.
    public func reregister() async throws {
        try requireSignedBuild()
        if [.enabled, .requiresApproval].contains(service.status) { try await unregisterForRestart() }
        var budget = Self.restartWaitLimit
        try await waitForHelperExit(budget: &budget)
        try await registerWithRetries(budget: &budget)
        try requireEnabled()
    }

    private func unregisterForRestart() async throws {
        do {
            try await service.unregister()
        } catch {
            // A daemon that is already gone needs no unregistration.
            guard HelperRegistrationFailure.classify(error) == .notRegistered else {
                throw HelperRegistrationFailure.error(for: error)
            }
        }
    }

    /// Returns once the daemon is not enabled and no helper process runs, or after `exitTimeLimit`.
    /// After the limit the register attempts still run; their failure names the cause.
    func waitForHelperExit(budget: inout Duration) async throws {
        var waited = Duration.zero
        while waited < Self.exitTimeLimit, budget >= Self.exitPollInterval,
            service.status == .enabled || processes.isHelperRunning()
        {
            try await pause(Self.exitPollInterval)
            waited += Self.exitPollInterval
            budget -= Self.exitPollInterval
        }
    }

    private func registerWithRetries(budget: inout Duration) async throws {
        for attempt in 1...Self.registerAttempts {
            do {
                try registerIfNeeded()
                return
            } catch {
                let transient = HelperRegistrationFailure.classify(error) == .transient
                guard transient, attempt < Self.registerAttempts, budget >= Self.registerRetryDelay else {
                    throw HelperRegistrationFailure.error(for: error)
                }
            }
            try await pause(Self.registerRetryDelay)
            budget -= Self.registerRetryDelay
            try await waitForHelperExit(budget: &budget)
        }
    }
}
