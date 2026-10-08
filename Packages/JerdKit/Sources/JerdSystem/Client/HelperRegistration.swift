import JerdFoundation

/// Registers and unregisters the helper daemon after the user's approval in the app.
///
/// Registration needs an Apple-signed build. A new daemon can report `notFound` before its first
/// registration, and `register()` can throw while macOS keeps the registration waiting for approval
/// in System Settings; that error is ignored when the state is then `requiresApproval` or `enabled`.
/// Every other failure becomes a `JerdError` that names what to do (`HelperRegistrationFailure`).
public struct HelperRegistration: Sendable {
    let service: any DaemonServiceControlling
    let processes: any HelperProcessInspecting
    let requireSignedBuild: @Sendable () throws -> Void
    /// Waits between two checks of the old helper, and between two register attempts.
    let pause: @Sendable (Duration) async throws -> Void

    public init(
        service: any DaemonServiceControlling = SMAppDaemonService(),
        processes: any HelperProcessInspecting = HelperProcessTable(),
        requireSignedBuild: @escaping @Sendable () throws -> Void = { _ = try CodeSigningPolicy.currentTeamID() },
        pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.service = service
        self.processes = processes
        self.requireSignedBuild = requireSignedBuild
        self.pause = pause
    }

    public var availability: HelperAvailability { service.status }

    /// Registers the daemon when needed and requires it to be enabled.
    public func register() throws {
        try requireSignedBuild()
        do {
            try registerIfNeeded()
        } catch {
            throw HelperRegistrationFailure.error(for: error)
        }
        try requireEnabled()
    }

    public func unregister() async throws {
        do {
            try await service.unregister()
        } catch {
            throw HelperRegistrationFailure.error(for: error)
        }
    }

    /// Calls `SMAppService.register()` unless the daemon is registered. Throws the raw error.
    func registerIfNeeded() throws {
        guard [.notRegistered, .notFound].contains(service.status) else { return }
        do {
            try service.register()
        } catch {
            guard [.requiresApproval, .enabled].contains(service.status) else { throw error }
        }
    }

    func requireEnabled() throws {
        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            throw JerdError.unavailable(
                "Allow Jerd in System Settings → General → Login Items & Extensions, then retry the operation."
            ).with(.openLoginItems)
        case .notRegistered, .notFound:
            // Not a Login Items refusal: the remedy is to register again, not to allow the helper.
            throw JerdError.unavailable(
                "The Jerd helper is not registered. Keep Jerd in Applications, then click Reconnect Helper…. If it "
                    + "fails again, check Login Items & Extensions."
            ).with(.reconnectHelper)
        }
    }
}
