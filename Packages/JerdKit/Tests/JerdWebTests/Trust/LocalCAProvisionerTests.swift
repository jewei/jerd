import Darwin
import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdWeb

@Suite struct LocalCAProvisionerTests {
    private func environment(_ folder: TemporaryDirectory) -> EnvironmentLayout {
        DataLayout(root: folder.url).environment
    }

    @Test func aNewInstallationGetsAJerdMadeCAThatMaySignOnlyTestNames() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = environment(folder)
        let authority = try LocalCAProvisioner(environment: environment).provision(
            installationID: Certificates.installationID)
        #expect(try NameConstraintsInspection.inspect(certificate: authority.der) == .limitedToTest)
        #expect(try LocalCertificateAuthority.read(environment.constrainedRootCertificateFile) == authority)
        #expect(FileProbe.presence(at: environment.legacyRootCertificateFile) == .absent)
        for file in [environment.constrainedRootKeyFile, environment.constrainedRootCertificateFile] {
            var info = stat()
            #expect(lstat(file.path, &info) == 0 && info.st_mode & 0o777 == 0o600, "\(file.lastPathComponent)")
        }
        #expect(ActiveAuthority.resolve(environment, installationID: Certificates.installationID).id == "jerd-2")
    }

    @Test func theSavedCAIsKeptAndChecked() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let provisioner = LocalCAProvisioner(environment: environment(folder))
        let first = try provisioner.provision(installationID: Certificates.installationID)
        #expect(try provisioner.provision(installationID: Certificates.installationID) == first)
        #expect(throws: JerdError.self) { try provisioner.provision(installationID: UUID()) }
    }

    /// An installation with the CA that Caddy made keeps it; Jerd makes no second CA.
    @Test func anInstallationWithTheLegacyCAKeepsIt() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = environment(folder)
        try Certificates.install(in: environment)
        let authority = try LocalCAProvisioner(environment: environment).provision(
            installationID: Certificates.installationID)
        #expect(authority == (try Certificates.authority()))
        #expect(FileProbe.presence(at: environment.constrainedRootCertificateFile) == .absent)
        #expect(ActiveAuthority.resolve(environment, installationID: Certificates.installationID).id == "jerd")
        #expect(ActiveAuthority.rootCertificateFile(environment) == environment.legacyRootCertificateFile)
    }

    @Test func creationWaitsForNoOtherHolderOfTheEnvironmentLock() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = environment(folder)
        try OwnedDirectory.create(environment.processesDirectory)
        let held = try InstanceLock.acquire(at: environment.recoveryLockFile, messages: WebEnvironmentLock.messages)
        defer { held.release() }
        #expect(throws: JerdError.locked("Another Jerd session is using this web environment.")) {
            try LocalCAProvisioner(environment: environment).provision(installationID: Certificates.installationID)
        }
        #expect(FileProbe.presence(at: environment.constrainedRootKeyFile) == .absent)
    }

    /// A damaged root stays in place; Jerd never replaces it with a new CA.
    @Test func aCorruptRootIsPreserved() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = environment(folder)
        try OwnedDirectory.create(environment.authorityDirectory("jerd-2"))
        try AtomicFile.write(Data("damaged".utf8), to: environment.constrainedRootCertificateFile)
        #expect(throws: JerdError.self) {
            try LocalCAProvisioner(environment: environment).provision(installationID: Certificates.installationID)
        }
        #expect(contents(environment.constrainedRootCertificateFile) == Data("damaged".utf8))
    }
}
