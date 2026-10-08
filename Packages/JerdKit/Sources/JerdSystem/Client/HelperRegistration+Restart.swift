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

    /// Registers the daemon again, so launchd starts the helper file of this app. It changes no hosts
    /// or trust.
    ///
    /// `SMAppService.unregister()` returns when it stopped the old job, but the old process can
    /// still be exiting, and a `register()` then fails with "Operation not permitted" and leaves the
    /// login item off. So this waits until the daemon is no longer enabled and no helper process
    /// runs (at most `exitTimeLimit`), and retries a transient failure a few times.
    public func reregister() async throws {
        try requireSignedBuild()
        if [.enabled, .requiresApproval].contains(service.status) { try await unregisterForRestart() }
        try await waitForHelperExit()
        try await registerWithRetries()
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
    func waitForHelperExit() async throws {
        var waited = Duration.zero
        while waited < Self.exitTimeLimit, service.status == .enabled || processes.isHelperRunning() {
            try await pause(Self.exitPollInterval)
            waited += Self.exitPollInterval
        }
    }

    private func registerWithRetries() async throws {
        for attempt in 1...Self.registerAttempts {
            do {
                try registerIfNeeded()
                return
            } catch {
                let transient = HelperRegistrationFailure.classify(error) == .transient
                guard transient, attempt < Self.registerAttempts else {
                    throw HelperRegistrationFailure.error(for: error)
                }
            }
            try await pause(Self.registerRetryDelay)
            try await waitForHelperExit()
        }
    }
}
