import CryptoKit
import Foundation
import Security
import Testing

@testable import JerdFoundation

@Suite struct BasicConstraintsInspectionTests {
    let key = P256.Signing.PrivateKey()

    /// A self-signed certificate with the subject key identifier and `extensions`.
    private func certificate(_ extensions: [CertificateBuilder.Extension]) throws -> Data {
        let identifier = CertificateBuilder.Extension(
            identifier: CertificateObjectIdentifier.subjectKeyIdentifier, isCritical: false,
            value: DERWriter.octetString(CertificateBuilder.keyIdentifier(of: key.publicKey)))
        return try LocalRootTemplate.builder(
            commonName: "x", publicKey: key.publicKey, now: Date(), extensions: [identifier] + extensions
        ).signed(by: key)
    }

    private func basicConstraints(_ value: Data, isCritical: Bool = true) -> CertificateBuilder.Extension {
        .init(identifier: CertificateObjectIdentifier.basicConstraints, isCritical: isCritical, value: value)
    }

    /// The earlier rule: Security.framework's Basic Constraints property "Certificate Authority".
    private func securityFrameworkSaysAuthority(_ der: Data) throws -> Bool {
        let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
        let values = SecCertificateCopyValues(certificate, [kSecOIDBasicConstraints] as CFArray, nil) as? [String: Any]
        let constraint = values?[kSecOIDBasicConstraints as String] as? [String: Any]
        let properties = constraint?[kSecPropertyKeyValue as String] as? [[String: Any]] ?? []
        return properties.contains { property in
            let value = property[kSecPropertyKeyValue as String]
            return property[kSecPropertyKeyLabel as String] as? String == "Certificate Authority"
                && (value as? String == "Yes" || (value as? NSNumber)?.boolValue == true)
        }
    }

    @Test func jerdsRootAndTheCaddyFormAreAuthorities() throws {
        let constrained = try LocalRootTemplate.certificate(commonName: "x", key: key, now: Date())
        let plain = try LocalRootTemplate.builder(
            commonName: "x", publicKey: key.publicKey, now: Date(),
            extensions: LocalRootTemplate.caExtensions(for: key.publicKey)
        ).signed(by: key)
        for der in [constrained, plain] {
            #expect(try BasicConstraintsInspection.isAuthority(certificate: der))
            #expect(try securityFrameworkSaysAuthority(der))
        }
    }

    /// Each form gives the same answer as Security.framework, also a non-critical extension.
    @Test func theAnswerMatchesSecurityFramework() throws {
        let cases: [([CertificateBuilder.Extension], Bool)] = [
            ([], false),
            ([basicConstraints(DERWriter.sequence([]))], false),
            ([basicConstraints(DERWriter.sequence([DERWriter.boolean(false)]))], false),
            ([basicConstraints(DERWriter.sequence([DERWriter.boolean(true)]), isCritical: false)], true),
            (
                [
                    basicConstraints(
                        DERWriter.sequence([DERWriter.boolean(true), DERWriter.unsignedInteger(Data([0]))]))
                ], true
            ),
        ]
        for (extensions, expected) in cases {
            let der = try certificate(extensions)
            #expect(try BasicConstraintsInspection.isAuthority(certificate: der) == expected)
            #expect(try securityFrameworkSaysAuthority(der) == expected)
        }
    }

    @Test func anUnexpectedFormIsNeverAnAuthority() throws {
        let forms = [
            DERWriter.sequence([DERWriter.element(tag: 0x01, Data([0x01]))]),
            DERWriter.sequence([DERWriter.unsignedInteger(Data([0])), DERWriter.boolean(true)]),
            DERWriter.set([DERWriter.boolean(true)]),
            DERWriter.boolean(true),
        ]
        for form in forms {
            #expect(try !BasicConstraintsInspection.isAuthority(certificate: certificate([basicConstraints(form)])))
        }
    }

    @Test func aRepeatedExtensionOrInvalidDERThrows() throws {
        let authority = basicConstraints(DERWriter.sequence([DERWriter.boolean(true)]))
        let repeated = try certificate([authority, authority])
        #expect(throws: JerdError.invalid("The CA repeats a certificate extension.")) {
            try BasicConstraintsInspection.isAuthority(certificate: repeated)
        }
        for der in [Data(), Data("not DER".utf8), Data([0x30, 0x00])] {
            #expect(throws: JerdError.self) { try BasicConstraintsInspection.isAuthority(certificate: der) }
        }
        let trailing = try certificate([basicConstraints(DERWriter.sequence([DERWriter.boolean(true)]) + Data([0]))])
        #expect(throws: JerdError.self) { try BasicConstraintsInspection.isAuthority(certificate: trailing) }
    }
}
