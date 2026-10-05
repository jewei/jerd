/// How the helper trusts the installation CA. The raw values match the helper's saved form.
public enum HTTPSTrustPolicy: String, Codable, Hashable, Sendable {
    /// Legacy: one trust entry per hostname. Chromium ignores it, so sites need new approval.
    case hostnames
    /// One unrestricted SSL-server trust entry. Jerd always requests this policy.
    case serverTLS
}
