import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

@Suite struct CertificateIdentityTests {
    @Test func acceptsTheInstallationCA() throws {
        let der = try Fixture.certificate()
        let certificate = try InstallationCertificate(installationID: Fixture.installationID, der: der)
        #expect(certificate.sha256 == FileDigest.hexSHA256(of: der))
        #expect(certificate.sha256.count == 64)
    }

    @Test func decodesPEMWithSurroundingWhitespace() throws {
        let pem = try Fixture.data("Certificates/jerd-ca.pem")
        let padded = Data(("\n  " + String(decoding: pem, as: UTF8.self) + "\n\n").utf8)
        #expect(try CertificateIdentity.decodePEM(padded) == Fixture.certificate())
        let certificate = try InstallationCertificate(installationID: Fixture.installationID, pem: pem)
        #expect(certificate.der == (try Fixture.certificate()))
    }

    @Test(arguments: [
        "", "not pem", "-----BEGIN CERTIFICATE-----\n!!!\n-----END CERTIFICATE-----",
        "-----BEGIN CERTIFICATE----------END CERTIFICATE-----",
    ])
    func refusesInvalidPEM(text: String) {
        #expect(throws: JerdError.invalid("The Jerd CA certificate is not valid PEM.")) {
            try CertificateIdentity.decodePEM(Data(text.utf8))
        }
    }

    @Test func refusesASecondCertificateAfterTheFirst() throws {
        let pem = String(decoding: try Fixture.data("Certificates/jerd-ca.pem"), as: UTF8.self)
        #expect(throws: JerdError.self) { try CertificateIdentity.decodePEM(Data((pem + pem).utf8)) }
    }

    @Test func refusesOversizedOrNonUTF8PEM() {
        let message = JerdError.invalid("The Jerd CA certificate is invalid.")
        #expect(throws: message) { try CertificateIdentity.decodePEM(Data(count: 16_384)) }
        #expect(throws: message) { try CertificateIdentity.decodePEM(Data([0xFF, 0xFE])) }
    }

    @Test func refusesBytesThatAreNotACertificate() {
        #expect(throws: JerdError.invalid("The Jerd CA certificate is invalid.")) {
            try InstallationCertificate(installationID: Fixture.installationID, der: Data("not a cert".utf8))
        }
    }

    @Test(arguments: [
        ("jerd-ca", Fixture.otherInstallationID), ("wrong-name", Fixture.installationID),
        ("not-self-issued", Fixture.installationID), ("jerd-ca-other", Fixture.installationID),
    ])
    func refusesAnotherInstallationsOrForeignCA(name: String, installationID: UUID) throws {
        let der = try Fixture.certificate(name)
        #expect(throws: JerdError.invalid("Only this installation's Jerd root CA can be trusted.")) {
            try InstallationCertificate(installationID: installationID, der: der)
        }
    }

    @Test func refusesACertificateThatIsNotACA() throws {
        let der = try Fixture.certificate("not-ca")
        #expect(throws: JerdError.invalid("The certificate is not a certificate authority.")) {
            try InstallationCertificate(installationID: Fixture.installationID, der: der)
        }
    }
}
