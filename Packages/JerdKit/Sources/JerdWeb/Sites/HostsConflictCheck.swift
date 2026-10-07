import Foundation
import JerdFoundation

/// A read-only check of `/etc/hosts` text before a hostname is registered.
///
/// It applies `HostsConflictRule`, the same section rule that the helper applies before it writes,
/// so a hostname that passes here is not refused by the helper for a hosts mapping.
public enum HostsConflictCheck {
    /// True when `hostname` is mapped outside Jerd's section, or inside a section that something
    /// other than Jerd changed (for example a `::1` line). Comments (`#` to the end of a line) are ignored.
    public static func hasConflict(hostname: String, hostsText: String) -> Bool {
        HostsConflictRule.hasConflict(hostname: hostname, in: Data(hostsText.utf8))
    }
}
