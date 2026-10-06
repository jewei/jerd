import Foundation
import Security
import Testing

@testable import JerdSystem

@Suite struct TrustSettingsPolicyTests {

    @Test func serverTLSIsOneUnrestrictedSSLServerEntry() {
        let entries = TrustSettingsPolicy.make(.serverTLS)
        #expect(entries.count == 1)
        #expect(entries[0][kSecTrustSettingsPolicyString as String] == nil)
        #expect(TrustSettingsPolicy.matches(entries, .serverTLS))
    }

    @Test func hostnamePolicyHasOneEntryPerHostname() throws {
        let hosts = try ValidatedHostnames(["b.test", "a.test"])
        let entries = TrustSettingsPolicy.make(.hostnames(hosts))
        #expect(entries.compactMap { $0[kSecTrustSettingsPolicyString as String] as? String } == ["a.test", "b.test"])
        #expect(TrustSettingsPolicy.matches(entries, .hostnames(hosts)))
        #expect(!TrustSettingsPolicy.matches(entries, .hostnames(try ValidatedHostnames(["a.test"]))))
    }

    @Test func thePoliciesNeverMatchEachOther() throws {
        let hosts = try ValidatedHostnames(["b.test", "a.test"])
        #expect(!TrustSettingsPolicy.matches(TrustSettingsPolicy.make(.serverTLS), .hostnames(hosts)))
        #expect(!TrustSettingsPolicy.matches(TrustSettingsPolicy.make(.hostnames(hosts)), .serverTLS))
    }

    @Test func acceptsTheStoredSSLServerPolicyName() {
        var entry = TrustSettingsPolicy.make(.serverTLS)[0]
        entry["kSecTrustSettingsPolicyName"] = "sslServer"
        #expect(TrustSettingsPolicy.matches([entry], .serverTLS))
    }

    @Test(arguments: ["sslClient", "basicX509", ""])
    func refusesAnotherPolicyName(name: String) {
        var entry = TrustSettingsPolicy.make(.serverTLS)[0]
        entry["kSecTrustSettingsPolicyName"] = name
        #expect(!TrustSettingsPolicy.matches([entry], .serverTLS))
    }

    @Test func refusesAnExtraKeyOrAnotherResult() {
        var extra = TrustSettingsPolicy.make(.serverTLS)[0]
        extra[kSecTrustSettingsAllowedError as String] = NSNumber(value: -1)
        #expect(!TrustSettingsPolicy.matches([extra], .serverTLS))
        var result = TrustSettingsPolicy.make(.serverTLS)[0]
        result[kSecTrustSettingsResult as String] = NSNumber(value: SecTrustSettingsResult.trustAsRoot.rawValue)
        #expect(!TrustSettingsPolicy.matches([result], .serverTLS))
    }

    @Test func refusesClientOrBasicPolicies() {
        for policy in [SecPolicyCreateSSL(false, nil), SecPolicyCreateBasicX509()] {
            var entry = TrustSettingsPolicy.make(.serverTLS)[0]
            entry[kSecTrustSettingsPolicy as String] = policy
            #expect(!TrustSettingsPolicy.matches([entry], .serverTLS))
        }
    }

    @Test func refusesRepeatedOrMissingEntries() throws {
        let hosts = try ValidatedHostnames(["b.test", "a.test"])
        let one = TrustSettingsPolicy.make(.hostnames(hosts))[0]
        #expect(!TrustSettingsPolicy.matches([one, one], .hostnames(hosts)))
        #expect(!TrustSettingsPolicy.matches([], .serverTLS))
        #expect(
            !TrustSettingsPolicy.matches(
                TrustSettingsPolicy.make(.serverTLS) + TrustSettingsPolicy.make(.serverTLS), .serverTLS))
    }

    @Test func scopeFollowsThePolicy() throws {
        let hosts = try ValidatedHostnames(["b.test", "a.test"])
        #expect(TrustScope(policy: .serverTLS, hostnames: hosts) == .serverTLS)
        #expect(TrustScope(policy: .hostnames, hostnames: hosts) == .hostnames(hosts))
        #expect(TrustScope.hostnames(hosts).policy == .hostnames)
    }
}
