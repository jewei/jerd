import Foundation

/// The one rule that decides if a hostname is already mapped by someone other than Jerd.
///
/// The app checks it before it registers a hostname, and the helper applies the same parser
/// (`HostsSectionLayout`) before it writes. A mapping is Jerd's own only inside a section that the
/// helper accepts: exact markers and only `127.0.0.1 <name>` lines. The helper's rule wins over the
/// old app rule, which also accepted `::1` and an unpaired BEGIN marker: the helper is the writer,
/// it never writes `::1`, and it refuses to replace a section with any other line. Accepting such
/// a section in the app let a hostname pass the app check and then fail in the helper.
public enum HostsConflictRule {
    /// True when `hostname` is mapped outside a valid Jerd section, or inside a section that
    /// something other than Jerd changed. A file that the parser refuses (too large, not UTF-8, or
    /// invalid markers) has no valid section, so every mapping in it counts.
    public static func hasConflict(hostname: String, in data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        let layout: HostsSectionLayout
        do {
            layout = try HostsSectionLayout.parse(data)
        } catch {
            // The helper refuses this file too. No line in it is Jerd's own.
            return HostsMapping.hasMapping(of: hostname, in: text)
        }
        if HostsMapping.hasMapping(of: hostname, in: layout.outsideText) { return true }
        guard let section = layout.section, HostsMapping.hasMapping(of: hostname, in: text) else { return false }
        // Jerd writes lowercase names only, so the exact name must be in an unchanged section.
        return !(section.mappedNames ?? []).contains(hostname.lowercased())
    }
}
