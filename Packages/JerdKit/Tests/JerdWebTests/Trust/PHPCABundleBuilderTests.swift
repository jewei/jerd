import Darwin
import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

/// A fixed trust answer for one isolated CA. No trust store changes.
struct FixedTrust: TrustDecisionPort {
    var trusted: Bool

    func isTrustedForServerTLS(_ der: Data) throws -> Bool { trusted }
}

@Suite struct PHPCABundleBuilderTests {
    let roots = Data("-----BEGIN CERTIFICATE-----\nROOTS\n-----END CERTIFICATE-----\n".utf8)

    func builder(_ folder: TemporaryDirectory, trusted: Bool = true, roots: Data? = nil) throws -> PHPCABundleBuilder {
        let file = folder.path("cert.pem")
        try AtomicFile.write(roots ?? self.roots, to: file)
        return PHPCABundleBuilder(trust: FixedTrust(trusted: trusted), systemRoots: file, systemRootsOwner: geteuid())
    }

    @Test func aTrustedCAGivesTheSystemRootsFollowedByTheCA() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        try Certificates.install(in: environment)
        let output = folder.path("out/php-ca.pem")
        let bundle = try builder(folder).prepare(
            rootCertificate: environment.rootCertificateFile, installationID: Certificates.installationID,
            output: output)
        #expect(bundle == output)
        #expect(contents(output) == roots + Data("\n".utf8) + (try Certificates.pem()))
        #expect(mode(output) == 0o600)
    }

    @Test func anUnchangedBundleIsNotRewritten() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        try Certificates.install(in: environment)
        let output = folder.path("php-ca.pem")
        let builder = try builder(folder)
        _ = try builder.prepare(rootCertificate: environment.rootCertificateFile, installationID: nil, output: output)
        let first = try FileManager.default.attributesOfItem(atPath: output.path)[.systemFileNumber] as? Int
        _ = try builder.prepare(rootCertificate: environment.rootCertificateFile, installationID: nil, output: output)
        #expect(try FileManager.default.attributesOfItem(atPath: output.path)[.systemFileNumber] as? Int == first)
    }

    @Test func noCAOrAnUntrustedCAGivesNoBundle() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        let output = folder.path("php-ca.pem")
        #expect(
            try builder(folder).prepare(
                rootCertificate: environment.rootCertificateFile, installationID: nil, output: output) == nil)
        try Certificates.install(in: environment)
        #expect(
            try builder(folder, trusted: false).prepare(
                rootCertificate: environment.rootCertificateFile, installationID: nil, output: output) == nil)
        #expect(isAbsent(output))
    }

    @Test func emptySystemRootsAndAForeignCAAreRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        try Certificates.install(in: environment)
        let output = folder.path("php-ca.pem")
        #expect(throws: JerdError.unavailable("The macOS CA file contains no certificates.")) {
            try builder(folder, roots: Data("nothing".utf8)).prepare(
                rootCertificate: environment.rootCertificateFile, installationID: nil, output: output)
        }
        #expect(throws: JerdError.self) {
            try builder(folder).prepare(
                rootCertificate: environment.rootCertificateFile, installationID: UUID(), output: output)
        }
    }

    @Test func theCLIBundleNeedsAnInstallationIdentity() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        #expect(try builder(folder).prepareForCLI(layout: layout) == nil)
        try Certificates.install(in: layout.environment)
        #expect(try builder(folder).prepareForCLI(layout: layout) == layout.runtimes.cliCABundleFile)
        try AtomicFile.write(Data("broken".utf8), to: layout.environment.installationIDFile)
        #expect(throws: JerdError.corrupt("The installation identity is invalid. It was preserved.")) {
            try builder(folder).prepareForCLI(layout: layout)
        }
    }

    @Test func theRealSystemRootsAreReadable() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let environment = DataLayout(root: folder.url).environment
        try Certificates.install(in: environment)
        let builder = PHPCABundleBuilder(trust: FixedTrust(trusted: true))
        let output = folder.path("php-ca.pem")
        _ = try builder.prepare(rootCertificate: environment.rootCertificateFile, installationID: nil, output: output)
        #expect(contents(output)?.starts(with: try Data(contentsOf: PHPCABundleBuilder.systemRootsFile)) == true)
    }
}
