import JerdFoundation

/// Registers and unregisters the helper daemon after the user's approval in the app.
///
/// Registration needs an Apple-signed build. A new daemon can report `notFound` before its first
/// registration, and `register()` can throw while macOS keeps the registration waiting for approval
/// in System Settings; that error is ignored when the state is then `requiresApproval` or `enabled`.
public struct HelperRegistration: Sendable {
    let service: any DaemonServiceControlling
    let requireSignedBuild: @Sendable () throws -> Void

    public init(
        service: any DaemonServiceControlling = SMAppDaemonService(),
        requireSignedBuild: @escaping @Sendable () throws -> Void = { _ = try CodeSigningPolicy.currentTeamID() }
    ) {
        self.service = service
        self.requireSignedBuild = requireSignedBuild
    }

    public var availability: HelperAvailability { service.status }

    /// Registers the daemon when needed and requires it to be enabled.
    public func register() throws {
        try requireSignedBuild()
        if [.notRegistered, .notFound].contains(service.status) {
            do {
                try service.register()
            } catch {
                guard [.requiresApproval, .enabled].contains(service.status) else { throw error }
            }
        }
        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            throw JerdError.unavailable(
                "Allow Jerd in System Settings → General → Login Items & Extensions, then retry the operation.")
        case .notRegistered, .notFound:
            throw JerdError.unavailable(
                "The Jerd helper is not enabled. Use a signed app in a stable location and check Login Items & Extensions."
            )
        }
    }

    /// Registers the daemon again. It changes no hosts or trust.
    public func reregister() async throws {
        try requireSignedBuild()
        if [.enabled, .requiresApproval].contains(service.status) { try await service.unregister() }
        try register()
    }

    public func unregister() async throws { try await service.unregister() }
}
