import Darwin

/// What a DNS lookup of a tunnel's public hostname found. A connected tunnel without a DNS record
/// is not reachable, and cloudflared cannot report that.
public enum PublicHostnameStatus: Equatable, Sendable {
    /// The name has at least one address.
    case resolves
    /// The name has no address: browsers cannot find it.
    case missing
    /// The lookup failed for another reason, for example no network. The app shows no warning.
    case unknown

    /// Only "no such name" and "no data" mean missing, so a network failure never shows a warning.
    package static func classify(status: Int32, addressCount: Int) -> Self {
        switch status {
        case 0: addressCount > 0 ? .resolves : .missing
        case EAI_NONAME, EAI_NODATA: .missing
        default: .unknown
        }
    }
}
