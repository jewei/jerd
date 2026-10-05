import Foundation
import Security
import Testing

@testable import JerdWeb

@Suite struct TrustDecisionTests {
    static func entry(
        server: Bool = true, result: SecTrustSettingsResult = .trustRoot, extra: [String: Any] = [:]
    ) -> [String: Any] {
        var entry: [String: Any] = [
            kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(server, nil),
            kSecTrustSettingsResult as String: NSNumber(value: result.rawValue),
        ]
        entry.merge(extra) { _, new in new }
        return entry
    }

    @Test func anUnrestrictedServerTrustEntryIsAccepted() {
        #expect(TrustDecision.accepts([Self.entry()]))
        #expect(TrustDecision.accepts([Self.entry(extra: [TrustDecision.policyNameKey: "sslServer"])]))
    }

    @Test func everyRestrictionOrOtherPolicyIsRefused() {
        let refused: [[[String: Any]]] = [
            [],
            [Self.entry(), Self.entry()],
            [Self.entry(extra: [TrustDecision.policyNameKey: "sslClient"])],
            [Self.entry(result: .deny)],
            [Self.entry(result: .trustAsRoot)],
            [Self.entry(extra: [kSecTrustSettingsPolicyString as String: "site.test"])],
            [Self.entry(server: false)],
            [Self.entry(extra: ["extra": 1])],
            [[kSecTrustSettingsResult as String: NSNumber(value: SecTrustSettingsResult.trustRoot.rawValue)]],
            [
                [
                    kSecTrustSettingsPolicy as String: "not a policy",
                    kSecTrustSettingsResult as String: NSNumber(value: SecTrustSettingsResult.trustRoot.rawValue),
                ]
            ],
            [
                [
                    kSecTrustSettingsPolicy as String: SecPolicyCreateBasicX509(),
                    kSecTrustSettingsResult as String: NSNumber(value: SecTrustSettingsResult.trustRoot.rawValue),
                ]
            ],
        ]
        for entries in refused { #expect(!TrustDecision.accepts(entries)) }
    }

    @Test func theIsolatedFixtureCAIsNotTrustedBySystemSettings() throws {
        #expect(try !SystemTrustDecision().isTrustedForServerTLS(try Certificates.authority().der))
        #expect(throws: (any Error).self) { try SystemTrustDecision().isTrustedForServerTLS(Data("x".utf8)) }
    }
}
