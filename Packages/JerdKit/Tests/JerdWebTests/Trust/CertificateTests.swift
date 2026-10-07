import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdWeb

@Suite struct CertificateTests {
    @Test func aPEMCertificateDecodesAndHasALowercaseFingerprint() throws {
        let authority = try Certificates.authority()
        #expect(authority.der.count > 100)
        #expect(authority.fingerprint == FileDigest.hexSHA256(of: authority.der))
        #expect(FileDigest.isSHA256Hex(authority.fingerprint))
    }

    @Test(arguments: [
        "", "not a certificate", "-----BEGIN CERTIFICATE-----\n%%%%\n-----END CERTIFICATE-----",
        "-----BEGIN CERTIFICATE-----", "-----BEGIN CERTIFICATE-----\nAAAA\n-----END PRIVATE KEY-----",
    ])
    func invalidPEMIsRefused(_ text: String) {
        #expect(throws: JerdError.invalid("The Jerd CA certificate is not valid PEM.")) {
            try LocalCertificateAuthority(pem: Data(text.utf8))
        }
    }

    @Test func largeOrBinaryFilesAreInvalid() {
        for data in [Data(repeating: 65, count: 16_384), Data([0xFF, 0xFE, 0xC3])] {
            #expect(throws: JerdError.invalid("The Jerd CA certificate is invalid.")) {
                try LocalCertificateAuthority(pem: data)
            }
        }
    }

    @Test func onlyThisInstallationsRootCAPasses() throws {
        try InstallationCertificate.validate(
            try Certificates.authority().der, installationID: Certificates.installationID)
        #expect(throws: JerdError.invalid("Only this installation's Jerd root CA can be trusted.")) {
            try InstallationCertificate.validate(try Certificates.authority().der, installationID: UUID())
        }
        #expect(throws: JerdError.invalid("Only this installation's Jerd root CA can be trusted.")) {
            try InstallationCertificate.validate(
                try Certificates.authority("other-ca").der, installationID: Certificates.installationID)
        }
        #expect(throws: JerdError.invalid("The certificate is not a certificate authority.")) {
            try InstallationCertificate.validate(
                try Certificates.authority("not-a-ca").der, installationID: Certificates.installationID)
        }
        #expect(throws: JerdError.invalid("The Jerd CA certificate is invalid.")) {
            try InstallationCertificate.validate(Data("test CA".utf8), installationID: Certificates.installationID)
        }
    }

    @Test func theRootCertificateIsReadOnlyAsAPrivateFile() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("root.crt")
        try AtomicFile.write(try Certificates.pem(), to: file)
        #expect(try LocalCertificateAuthority.read(file) == (try Certificates.authority()))
        let link = folder.path("link.crt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: JerdError.self) { try LocalCertificateAuthority.read(link) }
        let hard = folder.path("hard.crt")
        try FileManager.default.linkItem(at: file, to: hard)
        #expect(throws: JerdError.self) { try LocalCertificateAuthority.read(file) }
    }
}
