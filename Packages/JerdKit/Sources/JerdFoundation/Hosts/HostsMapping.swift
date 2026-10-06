/// Finds hosts-file lines that map a hostname.
public enum HostsMapping {
    /// True when a line of `contents` maps `hostname` (as an alias, any address, any letter case).
    ///
    /// The text after `#` is a comment. A line needs an address and at least one alias. Lines end
    /// at any newline character, so a CR is never part of a name.
    public static func hasMapping(of hostname: String, in contents: String) -> Bool {
        let wanted = hostname.lowercased()
        for line in contents.split(whereSeparator: \.isNewline) {
            let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let fields = content.split(whereSeparator: \.isWhitespace)
            guard fields.count > 1 else { continue }
            if fields.dropFirst().contains(where: { $0.lowercased() == wanted }) { return true }
        }
        return false
    }
}
