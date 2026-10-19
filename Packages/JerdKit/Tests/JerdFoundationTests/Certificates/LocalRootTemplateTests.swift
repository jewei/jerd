import CryptoKit
import Foundation
import Security
import Testing

@testable import JerdFoundation

/// The trust checks run in memory with the root as the only anchor. They change no keychain and
/// no trust setting, and they fetch nothing.
@Suite struct LocalRootTemplateTests {
    let rootKey = P256.Signing.PrivateKey()
    let now = Date()

    private func leaf(_ name: String, signedBy key: P256.Signing.PrivateKey, issuer: String) throws -> Data {
        let leafKey = P256.Signing.PrivateKey()
        let builder = CertificateBuilder(
            subjectCommonName: name, issuerCommonName: issuer, publicKey: leafKey.publicKey,
            serialNumber: CertificateBuilder.randomSerialNumber(), notBefore: now.addingTimeInterval(-60),
            notAfter: now.addingTimeInterval(7 * 86_400), extensions: Self.serverExtensions(name))
        return try builder.signed(by: key)
    }

    private static func serverExtensions(_ name: String) -> [CertificateBuilder.Extension] {
        [
            .init(
                identifier: CertificateObjectIdentifier.keyUsage, isCritical: true,
                value: DERWriter.bitString(Data([0x80]), unusedBits: 7)),
            .init(
                identifier: CertificateObjectIdentifier.extendedKeyUsage, isCritical: false,
                value: DERWriter.sequence([DERWriter.objectIdentifier(CertificateObjectIdentifier.serverAuthentication)]
                )),
            .init(
                identifier: CertificateObjectIdentifier.subjectAlternativeName, isCritical: false,
                value: DERWriter.sequence([DERWriter.contextSpecific(2, constructed: false, Data(name.utf8))])),
        ]
    }

    /// True when macOS trusts `leaf` for TLS to `host`, with `root` as the only anchor.
    private func trusts(_ leaf: Data, chain: [Data] = [], root: Data, host: String) throws -> Bool {
        let certificates = try ([leaf] + chain + [root]).map {
            try #require(SecCertificateCreateWithData(nil, $0 as CFData))
        }
        var trust: SecTrust?
        #expect(
            SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateSSL(true, host as CFString), &trust)
                == errSecSuccess)
        let checked = try #require(trust)
        SecTrustSetAnchorCertificates(checked, [certificates.last!] as CFArray)
        SecTrustSetAnchorCertificatesOnly(checked, true)
        SecTrustSetNetworkFetchAllowed(checked, false)
        return SecTrustEvaluateWithError(checked, nil)
    }

    @Test func macOSReadsTheRootAndItsKey() throws {
        let root = try LocalRootTemplate.certificate(commonName: "Jerd Local CA test", key: rootKey, now: now)
        let certificate = try #require(SecCertificateCreateWithData(nil, root as CFData))
        #expect(SecCertificateCopySubjectSummary(certificate) as String? == "Jerd Local CA test")
        #expect(SecCertificateCopyKey(certificate) != nil)
        #expect(try NameConstraintsInspection.inspect(certificate: root) == .limitedToTest)
    }

    @Test func macOSTrustsATestNameAndRefusesAnyOtherName() throws {
        let name = "Jerd Local CA test"
        let root = try LocalRootTemplate.certificate(commonName: name, key: rootKey, now: now)
        #expect(try trusts(leaf("app.test", signedBy: rootKey, issuer: name), root: root, host: "app.test"))
        #expect(try trusts(leaf("a.b.app.test", signedBy: rootKey, issuer: name), root: root, host: "a.b.app.test"))
        #expect(try !trusts(leaf("example.com", signedBy: rootKey, issuer: name), root: root, host: "example.com"))
        #expect(try !trusts(leaf("app.testing", signedBy: rootKey, issuer: name), root: root, host: "app.testing"))
    }

    /// The control: the same leaf under a root without constraints is trusted, so the refusal
    /// above comes from the name constraints.
    @Test func withoutTheConstraintsTheSameNameIsTrusted() throws {
        let name = "Jerd Local CA test"
        let root = try LocalRootTemplate.builder(
            commonName: name, publicKey: rootKey.publicKey, now: now,
            extensions: LocalRootTemplate.caExtensions(for: rootKey.publicKey)
        ).signed(by: rootKey)
        #expect(try NameConstraintsInspection.inspect(certificate: root) == .unconstrained)
        #expect(try trusts(leaf("example.com", signedBy: rootKey, issuer: name), root: root, host: "example.com"))
    }

    /// Caddy signs leaves with an intermediate. The constraints of the root apply below it.
    @Test func theConstraintsHoldBelowAnIntermediate() throws {
        let root = try LocalRootTemplate.certificate(commonName: "Root", key: rootKey, now: now)
        let middleKey = P256.Signing.PrivateKey()
        let middle = try LocalRootTemplate.builder(
            commonName: "Intermediate", publicKey: middleKey.publicKey, now: now,
            extensions: LocalRootTemplate.caExtensions(for: middleKey.publicKey)
        )
        var signedMiddle = middle
        signedMiddle.issuerCommonName = "Root"
        let middleDER = try signedMiddle.signed(by: rootKey)
        let good = try leaf("app.test", signedBy: middleKey, issuer: "Intermediate")
        let bad = try leaf("example.com", signedBy: middleKey, issuer: "Intermediate")
        #expect(try trusts(good, chain: [middleDER], root: root, host: "app.test"))
        #expect(try !trusts(bad, chain: [middleDER], root: root, host: "example.com"))
    }

    @Test func otherOrNonCriticalConstraintsAreNotJerds() throws {
        var extensions = LocalRootTemplate.caExtensions(for: rootKey.publicKey)
        extensions.append(
            .init(
                identifier: CertificateObjectIdentifier.nameConstraints, isCritical: false,
                value: LocalRootTemplate.nameConstraintsValue))
        let nonCritical = try LocalRootTemplate.builder(
            commonName: "x", publicKey: rootKey.publicKey, now: now, extensions: extensions
        ).signed(by: rootKey)
        #expect(try NameConstraintsInspection.inspect(certificate: nonCritical) == .otherConstraints)
        #expect(throws: JerdError.self) { try NameConstraintsInspection.inspect(certificate: Data([0x30, 0x00])) }
    }
}
