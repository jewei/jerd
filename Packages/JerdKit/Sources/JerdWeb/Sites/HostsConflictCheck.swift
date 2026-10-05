/// A read-only check of `/etc/hosts` text before a hostname is registered.
///
/// The helper validates its owned section again before it writes; this check only refuses a
/// hostname that another tool or the user already maps.
public enum HostsConflictCheck {
    /// The first line of Jerd's owned section.
    public static let sectionBegin = "# BEGIN JERD"
    /// The last line of Jerd's owned section.
    public static let sectionEnd = "# END JERD"

    /// True when `hostname` appears as an alias outside Jerd's section, or inside it with an
    /// address other than `127.0.0.1` or `::1`. Comments (`#` to the end of a line) are ignored.
    public static func hasConflict(hostname: String, hostsText: String) -> Bool {
        let wanted = hostname.lowercased()
        var owned = false
        for line in hostsText.components(separatedBy: .newlines) {
            if line == sectionBegin {
                owned = true
                continue
            }
            if line == sectionEnd {
                owned = false
                continue
            }
            let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let fields = content.split(whereSeparator: \.isWhitespace)
            guard fields.count > 1, fields.dropFirst().contains(where: { $0.lowercased() == wanted }) else { continue }
            if !owned || !["127.0.0.1", "::1"].contains(String(fields[0])) { return true }
        }
        return false
    }
}
