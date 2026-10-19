import Darwin
import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdWeb

/// The choice reads only whether the legacy root may exist.
@Suite struct ActiveAuthorityTests {
    let id = Certificates.installationID

    @Test func aLegacyFolderWithoutItsRootUsesTheJerdMadeCA() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        try OwnedDirectory.create(environment.authorityDirectory(EnvironmentLayout.legacyAuthorityID))
        try AtomicFile.write(
            Data("old".utf8), to: environment.authorityDirectory("jerd").appendingPathComponent("intermediate.crt"))
        #expect(ActiveAuthority.resolve(environment, installationID: id) == .constrainedInstallation(id))
    }

    /// When both CAs exist, for example during a migration, the legacy CA stays until it is retired.
    @Test func withBothCAsTheLegacyCAStays() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        _ = try LocalCAProvisioner(environment: environment).provision(installationID: id)
        try Certificates.install(in: environment)
        #expect(ActiveAuthority.resolve(environment, installationID: id) == .installation(id))
        #expect(ActiveAuthority.rootCertificateFile(environment) == environment.legacyRootCertificateFile)
    }

    /// A legacy folder that cannot be read keeps the legacy CA, so the load fails with a message
    /// and Jerd never makes a second CA.
    @Test func anUnreadableLegacyFolderKeepsTheLegacyCA() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        let legacy = environment.authorityDirectory(EnvironmentLayout.legacyAuthorityID)
        try OwnedDirectory.create(legacy)
        #expect(chmod(legacy.path, 0) == 0)
        defer { chmod(legacy.path, 0o700) }
        #expect(ActiveAuthority.resolve(environment, installationID: id) == .installation(id))
        #expect(throws: JerdError.self) {
            try LocalCAProvisioner(environment: environment).provision(installationID: id)
        }
        #expect(FileProbe.presence(at: environment.constrainedRootKeyFile) == .absent)
    }
}
