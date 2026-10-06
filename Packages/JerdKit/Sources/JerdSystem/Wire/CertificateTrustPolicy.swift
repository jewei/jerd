/// How macOS trusts the Jerd CA. The raw values are saved in helper records and sent over XPC.
public enum CertificateTrustPolicy: String, Codable, Sendable, CaseIterable, Comparable {
    /// One SSL rule per hostname (legacy; Chromium ignores it). Kept for v1 and v2 records and rollback.
    case hostnames
    /// One unrestricted SSL server rule. Safari and Chromium browsers accept it.
    case serverTLS

    /// The declaration order, so that lists of policies have one stable order.
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    private var rank: Int {
        switch self {
        case .hostnames: 0
        case .serverTLS: 1
        }
    }
}
