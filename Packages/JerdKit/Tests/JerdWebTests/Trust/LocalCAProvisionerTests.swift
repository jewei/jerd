import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdWeb

@Suite struct LocalCAProvisionerTests {
    /// A Caddy stand-in that writes the fixture CA where Caddy would.
    static func creatingCaddy(_ environment: EnvironmentLayout, status: Int32 = 0) -> ScriptedCommandRunner {
        ScriptedCommandRunner { _ in
            if status == 0 { try Certificates.install(in: environment) }
            return CommandResult(status: status, output: "caddy says no")
        }
    }

    @Test func aMissingCAIsCreatedWithAPKIOnlyValidation() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        let commands = Self.creatingCaddy(environment)
        let provisioner = LocalCAProvisioner(environment: environment, commands: commands)
        let authority = try await provisioner.provision(
            installationID: Certificates.installationID, caddy: Samples.caddy())
        #expect(authority == (try Certificates.authority()))
        let request = try #require(commands.requests.first)
        #expect(request.executable.path == "/local/caddy")
        #expect(request.arguments == ["validate", "--config", environment.prepareCAFile.path])
        #expect(request.workingDirectory == environment.root)
        #expect(
            request.environment == [
                "XDG_DATA_HOME": environment.certificatesDirectory.path,
                "XDG_CONFIG_HOME": environment.configurationDirectory.path,
            ])
        #expect(
            contents(environment.prepareCAFile)
                == (try CaddyConfigRenderer.renderAuthorityPreparation(
                    authority: .installation(Certificates.installationID), storage: environment.certificatesDirectory)))
    }

    @Test func anExistingCAIsLoadedWithoutACommand() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        try Certificates.install(in: environment)
        let commands = ScriptedCommandRunner()
        let provisioner = LocalCAProvisioner(environment: environment, commands: commands)
        _ = try await provisioner.provision(installationID: Certificates.installationID, caddy: Samples.caddy())
        #expect(commands.requests.isEmpty)
        await #expect(throws: JerdError.self) {
            try await provisioner.provision(installationID: UUID(), caddy: Samples.caddy())
        }
    }

    @Test func aFailedValidationReportsCaddysDiagnostics() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        let provisioner = LocalCAProvisioner(
            environment: environment, commands: Self.creatingCaddy(environment, status: 1))
        await #expect(throws: JerdError.processFailed("Cannot prepare the local CA: caddy says no")) {
            try await provisioner.provision(installationID: Certificates.installationID, caddy: Samples.caddy())
        }
    }

    @Test func creationWaitsForNoOtherHolderOfTheEnvironmentLock() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        try OwnedDirectory.create(environment.processesDirectory)
        let held = try InstanceLock.acquire(at: environment.recoveryLockFile, messages: WebEnvironmentLock.messages)
        defer { held.release() }
        let commands = Self.creatingCaddy(environment)
        let provisioner = LocalCAProvisioner(environment: environment, commands: commands)
        await #expect(throws: JerdError.locked("Another Jerd session is using this web environment.")) {
            try await provisioner.provision(installationID: Certificates.installationID, caddy: Samples.caddy())
        }
        #expect(commands.requests.isEmpty)
    }
}
