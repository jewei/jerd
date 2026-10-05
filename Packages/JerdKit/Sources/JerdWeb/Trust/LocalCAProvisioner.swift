import Foundation
import JerdFoundation
import JerdProcess

/// Creates the installation CA with Caddy when it is missing, then loads and checks it.
///
/// `caddy validate` with a PKI-only configuration creates the CA in Caddy's storage. It opens no
/// listener and never installs trust. Approval of the CA is the helper's job, not this type's.
public struct LocalCAProvisioner: Sendable {
    /// The timeout of the CA creation command.
    public static let commandTimeout: Duration = .seconds(15)

    private let environment: EnvironmentLayout
    private let commands: any CommandRunning

    public init(environment: EnvironmentLayout, commands: any CommandRunning = CommandRunner()) {
        self.environment = environment
        self.commands = commands
    }

    /// The installation CA, created first when `root.crt` is absent.
    ///
    /// Creation holds the web environment lock, so it cannot race the engine or recovery of
    /// another Jerd instance.
    public func provision(installationID: UUID, caddy: CaddyRuntime) async throws -> LocalCertificateAuthority {
        if FileProbe.presence(at: environment.rootCertificateFile) == .absent {
            try await create(installationID: installationID, caddy: caddy)
        }
        return try load(installationID: installationID)
    }

    /// The saved installation CA, read strictly and checked against the installation ID.
    public func load(installationID: UUID) throws -> LocalCertificateAuthority {
        let authority = try LocalCertificateAuthority.read(environment.rootCertificateFile)
        try InstallationCertificate.validate(authority.der, installationID: installationID)
        return authority
    }

    private func create(installationID: UUID, caddy: CaddyRuntime) async throws {
        for folder in [
            environment.configurationDirectory, environment.certificatesDirectory, environment.processesDirectory,
        ] {
            try OwnedDirectory.create(folder)
        }
        let lock = try InstanceLock.acquire(at: environment.recoveryLockFile, messages: WebEnvironmentLock.messages)
        defer { lock.release() }
        let file = environment.prepareCAFile
        try AtomicFile.write(
            try CaddyConfigRenderer.renderAuthorityPreparation(
                authority: .installation(installationID), storage: environment.certificatesDirectory),
            to: file)
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: caddy.path), arguments: ["validate", "--config", file.path],
            workingDirectory: environment.root,
            environment: [
                "XDG_DATA_HOME": environment.certificatesDirectory.path,
                "XDG_CONFIG_HOME": environment.configurationDirectory.path,
            ])
        let result = try await commands.run(request, timeout: Self.commandTimeout)
        guard result.succeeded else {
            throw JerdError.processFailed("Cannot prepare the local CA: \(result.diagnosticOutput)")
        }
    }
}
