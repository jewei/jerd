import Foundation
import Security

/// The pure rule that decides if saved macOS trust settings make a CA usable for PHP.
///
/// A PEM bundle cannot express denials or hostname limits, so only one unrestricted SSL-server
/// trust entry qualifies. This matches the `serverTLS` setting that the helper installs.
public enum TrustDecision {
    /// macOS adds this key when it stores a policy. It is not a public SDK constant.
    static let policyNameKey = "kSecTrustSettingsPolicyName"

    /// True for exactly one entry with the keys Result and Policy (plus an optional policy name
    /// `sslServer`), the result "trust root", and the Apple SSL server policy. A denial, a hostname
    /// limit, a legacy per-host entry, a client policy, or an extra key is false.
    public static func accepts(_ entries: [[String: Any]]) -> Bool {
        guard entries.count == 1, let entry = entries.first else { return false }
        var expectedKeys: Set<String> = [kSecTrustSettingsResult as String, kSecTrustSettingsPolicy as String]
        if let name = entry[policyNameKey] {
            guard name as? String == "sslServer" else { return false }
            expectedKeys.insert(policyNameKey)
        }
        guard Set(entry.keys) == expectedKeys,
            (entry[kSecTrustSettingsResult as String] as? NSNumber)?.uint32Value
                == SecTrustSettingsResult.trustRoot.rawValue
        else { return false }
        return isServerPolicy(entry[kSecTrustSettingsPolicy as String])
    }

    private static func isServerPolicy(_ value: Any?) -> Bool {
        guard let value, CFGetTypeID(value as CFTypeRef) == SecPolicyGetTypeID() else { return false }
        // The type ID check above proves that the value is a SecPolicy.
        let policy = unsafeDowncast(value as AnyObject, to: SecPolicy.self)
        guard let properties = SecPolicyCopyProperties(policy) as NSDictionary? else { return false }
        return properties[kSecPolicyOid] as? String == kSecPolicyAppleSSL as String
            && (properties[kSecPolicyClient] as? NSNumber)?.boolValue != true
    }
}
