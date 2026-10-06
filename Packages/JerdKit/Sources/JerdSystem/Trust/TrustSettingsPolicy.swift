import Foundation
import Security

/// Builds and strictly compares admin trust settings for the Jerd CA.
///
/// `.serverTLS` gives one entry: the SSL server policy with the result "trust root". `.hostnames`
/// gives one such entry per hostname with a policy string. Chromium ignores entries with a policy
/// string, so only `.serverTLS` works in Chromium browsers.
public enum TrustSettingsPolicy {
    /// The name that macOS adds to a stored SSL server policy. It is not a public SDK constant.
    static let policyNameKey = "kSecTrustSettingsPolicyName"

    /// The trust settings array to apply.
    public static func make(_ scope: TrustScope) -> [[String: Any]] {
        let base: [String: Any] = [
            kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, nil),
            kSecTrustSettingsResult as String: NSNumber(value: SecTrustSettingsResult.trustRoot.rawValue),
        ]
        switch scope {
        case .serverTLS:
            return [base]
        case .hostnames(let hostnames):
            return hostnames.strings.map { hostname in
                base.merging([kSecTrustSettingsPolicyString as String: hostname]) { $1 }
            }
        }
    }

    /// True only when `entries` are exactly the settings of `scope`: the same count, the SSL server
    /// policy, the result "trust root", no other key, and (for hostnames) each hostname once.
    public static func matches(_ entries: [[String: Any]], _ scope: TrustScope) -> Bool {
        let expectedNames: Set<String>
        switch scope {
        case .serverTLS: expectedNames = []
        case .hostnames(let hostnames): expectedNames = hostnames.set
        }
        guard entries.count == max(1, expectedNames.count) else { return false }
        var found: Set<String> = []
        for entry in entries {
            guard isSSLServerRoot(entry, withPolicyString: scope != .serverTLS) else { return false }
            if let name = entry[kSecTrustSettingsPolicyString as String] as? String {
                guard found.insert(name).inserted else { return false }
            }
        }
        return found == expectedNames
    }

    private static func isSSLServerRoot(_ entry: [String: Any], withPolicyString: Bool) -> Bool {
        var keys: Set<String> = [kSecTrustSettingsResult as String, kSecTrustSettingsPolicy as String]
        if withPolicyString { keys.insert(kSecTrustSettingsPolicyString as String) }
        if let name = entry[policyNameKey] {
            // Accept only the SSL server name; a stored SSL policy's properties can omit its client flag.
            guard name as? String == "sslServer" else { return false }
            keys.insert(policyNameKey)
        }
        guard Set(entry.keys) == keys,
            (entry[kSecTrustSettingsResult as String] as? NSNumber)?.uint32Value
                == SecTrustSettingsResult.trustRoot.rawValue,
            let value = entry[kSecTrustSettingsPolicy as String],
            CFGetTypeID(value as CFTypeRef) == SecPolicyGetTypeID()
        else { return false }
        // The type ID check above proves that the value is a SecPolicy.
        let policy = unsafeDowncast(value as AnyObject, to: SecPolicy.self)
        guard let properties = SecPolicyCopyProperties(policy) as NSDictionary? else { return false }
        return properties[kSecPolicyOid] as? String == kSecPolicyAppleSSL as String
            && (properties[kSecPolicyClient] as? NSNumber)?.boolValue != true
            && (!withPolicyString || entry[kSecTrustSettingsPolicyString as String] is String)
    }
}
