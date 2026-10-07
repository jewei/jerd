import Foundation
import JerdFoundation
import JerdProcess

/// The web layer's only path to the helper for setup changes.
///
/// Every change first stops the run through the coordinator (the helper changes hosts and trust
/// under it). The gateway checks no ports: the coordinator checks 80 and 443 right before it
/// leases them, which is the one place where they matter.
public actor SystemSetupGateway: SystemSetupManaging {
    private let environment: EnvironmentLayout
    private let system: any SystemSetupPort
    private let coordinator: any EnvironmentCoordinating
    private let provisioner: LocalCAProvisioner

    public init(
        layout: DataLayout, system: any SystemSetupPort, coordinator: any EnvironmentCoordinating,
        commands: any CommandRunning = CommandRunner()
    ) {
        environment = layout.environment
        self.system = system
        self.coordinator = coordinator
        provisioner = LocalCAProvisioner(environment: layout.environment, commands: commands)
    }

    public func status() async throws -> HTTPSSetupStatus {
        try await system.status()
    }

    public func localAuthority() throws -> InstallationAuthority? {
        try InstallationAuthority.read(environment)
    }

    /// The request always uses server-TLS trust. A missing CA is created only while nothing runs,
    /// because Caddy's storage then belongs to no live process.
    public func prepare(hostnames: [String], caddy: CaddyRuntime) async throws -> HTTPSSetup {
        let validated = try HostnamePolicy.validateSet(hostnames).map(\.value)
        let installationID = try InstallationIdentity(environment: environment).readOrCreate()
        if FileProbe.presence(at: environment.rootCertificateFile) == .absent, await coordinator.runningPlan() != nil {
            throw JerdError.unavailable("Stop the environment before preparing a missing CA.")
        }
        let authority = try await provisioner.provision(installationID: installationID, caddy: caddy)
        return HTTPSSetup(
            registration: HTTPSRegistration(
                installationID: installationID, hostnames: validated, certificateDER: authority.der,
                trustPolicy: .serverTLS))
    }

    public func apply(_ setup: HTTPSSetup) async throws {
        await coordinator.halt()
        try await system.configure(setup.registration)
    }

    public func removeHostnames(_ hostnames: Set<String>) async throws {
        let status = try await system.status()
        guard !hostnames.isDisjoint(with: status.hostnames) else { return }
        await coordinator.halt()
        var remaining = status
        remaining.hostnames = status.hostnames.filter { !hostnames.contains($0) }
        guard !remaining.hostnames.isEmpty else {
            try await system.removeSetup()
            return
        }
        guard let registration = remaining.registration else {
            throw JerdError.unavailable("The approved certificate record is missing.")
        }
        try await system.configure(registration)
    }

    public func restore(_ status: HTTPSSetupStatus) async throws {
        await coordinator.halt()
        if let registration = status.registration {
            try await system.configure(registration)
        } else {
            try await system.removeSetup()
        }
    }

    public func removeSetup() async throws {
        await coordinator.halt()
        try await system.removeSetup()
        await coordinator.markSetupRemoved()
    }
}
