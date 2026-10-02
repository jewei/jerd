import Foundation
import Security

/// The server-TLS policy is compatible with Chromium's macOS trust reader.
/// The legacy hostname policy is retained for existing records and rollback.
public enum CertificateTrustSettings {
    public static func make(policy: CertificateTrustPolicy, hostnames: [String]) throws -> [[String: Any]] {
        let hosts = try Hostname.validatedSet(hostnames)
        let base: [String: Any] = [
            kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, nil),
            kSecTrustSettingsResult as String: NSNumber(value: SecTrustSettingsResult.trustRoot.rawValue)
        ]
        if policy == .serverTLS { return [base] }
        return hosts.map { hostname in
            var entry = base
            entry[kSecTrustSettingsPolicyString as String] = hostname
            return entry
        }
    }

    public static func matches(_ entries: [[String: Any]], policy: CertificateTrustPolicy, hostnames: [String]) -> Bool {
        guard let hosts = try? Hostname.validatedSet(hostnames),
              entries.count == (policy == .serverTLS ? 1 : hosts.count) else { return false }
        var found: Set<String> = []
        for entry in entries {
            var expectedKeys = Set([kSecTrustSettingsResult as String, kSecTrustSettingsPolicy as String])
            if policy == .hostnames { expectedKeys.insert(kSecTrustSettingsPolicyString as String) }
            guard (entry[kSecTrustSettingsResult as String] as? NSNumber)?.uint32Value == SecTrustSettingsResult.trustRoot.rawValue,
                  Set(entry.keys) == expectedKeys,
                  let value = entry[kSecTrustSettingsPolicy as String], CFGetTypeID(value as CFTypeRef) == SecPolicyGetTypeID() else { return false }
            let ssl = value as! SecPolicy
            guard let properties = SecPolicyCopyProperties(ssl) as NSDictionary?,
                  properties[kSecPolicyOid] as? String == kSecPolicyAppleSSL as String,
                  (properties[kSecPolicyClient] as? NSNumber)?.boolValue != true else { return false }
            if policy == .serverTLS {
                guard entry[kSecTrustSettingsPolicyString as String] == nil else { return false }
            } else {
                guard let hostname = entry[kSecTrustSettingsPolicyString as String] as? String,
                      found.insert(hostname).inserted else { return false }
            }
        }
        return policy == .serverTLS || found == Set(hosts)
    }
}
