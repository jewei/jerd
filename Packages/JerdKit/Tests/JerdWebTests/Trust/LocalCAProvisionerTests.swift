import CryptoKit
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

    /// A crash between the two writes leaves a key without a certificate; the next provisioning
    /// makes a new pair, and the intermediate of an earlier root goes.
    @Test func aKeyWithoutACertificateGetsANewPairAndNoOldIntermediate() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = environment(folder)
        let authorityFolder = environment.authorityDirectory(EnvironmentLayout.constrainedAuthorityID)
        try OwnedDirectory.create(authorityFolder)
        try AtomicFile.write(Data("stale key".utf8), to: environment.constrainedRootKeyFile)
        let intermediate = authorityFolder.appendingPathComponent("intermediate.crt")
        try AtomicFile.write(Data("old intermediate".utf8), to: intermediate)
        _ = try LocalCAProvisioner(environment: environment).provision(installationID: Certificates.installationID)
        #expect(contents(environment.constrainedRootKeyFile) != Data("stale key".utf8))
        #expect(FileProbe.presence(at: intermediate) == .absent)
    }

    /// A lost or foreign key gives a message that a user can act on; both files stay.
    @Test func aMissingOrForeignKeyIsReportedAndKept() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = environment(folder)
        let provisioner = LocalCAProvisioner(environment: environment)
        _ = try provisioner.provision(installationID: Certificates.installationID)
        let foreign = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
        try AtomicFile.write(foreign, to: environment.constrainedRootKeyFile)
        #expect {
            try provisioner.provision(installationID: Certificates.installationID)
        } throws: { error in
            (error as? JerdError)?.kind == .corrupt
        }
        #expect(contents(environment.constrainedRootKeyFile) == foreign)
        try FileManager.default.removeItem(at: environment.constrainedRootKeyFile)
        #expect(throws: JerdError.self) { try provisioner.provision(installationID: Certificates.installationID) }
        #expect(FileProbe.presence(at: environment.constrainedRootCertificateFile) == .present)
    }

    /// The CA update makes Jerd's CA while the legacy CA stays active, and changes nothing of it.
    @Test func theConstrainedCAIsMadeBesideTheLegacyCA() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = environment(folder)
        try Certificates.install(in: environment)
        let legacy = contents(environment.legacyRootCertificateFile)
        let made = try LocalCAProvisioner(environment: environment).provisionConstrained(
            installationID: Certificates.installationID)
        #expect(try NameConstraintsInspection.inspect(certificate: made.der) == .limitedToTest)
        #expect(contents(environment.legacyRootCertificateFile) == legacy)
        #expect(ActiveAuthority.resolve(environment, installationID: Certificates.installationID).id == "jerd")
    }
}
