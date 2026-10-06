import Foundation
import JerdFoundation

/// Jerd's tracked section of the hosts file. Every byte outside the section is kept.
///
/// The section that Jerd writes (LF only, hostnames sorted):
/// `"\n# BEGIN JERD\n127.0.0.1 a.test\n127.0.0.1 b.test\n# END JERD\n"`. No hostnames means no section.
/// One rule reads a section for both `replacing` and `maps`, so a section that `replacing` accepts
/// is also reported as configured. The parser and its rule are `HostsSectionLayout` and
/// `HostsMapping` in JerdFoundation, which the app-side conflict check (`HostsConflictRule`) uses too.
public enum HostsSection {
    public static let beginMarker = HostsSectionLayout.beginMarker
    public static let endMarker = HostsSectionLayout.endMarker
    /// The only address that the section maps.
    public static let address = HostsSectionLayout.address
    /// The largest hosts file that Jerd reads or writes (bytes).
    public static let maximumSize = HostsSectionLayout.maximumSize

    /// The section text for `hostnames`, or "" when there are none.
    public static func render(_ hostnames: [Hostname]) -> String {
        guard !hostnames.isEmpty else { return "" }
        let lines = Set(hostnames).sorted().map { "\(address) \($0.value)" }
        return "\n\(beginMarker)\n" + lines.joined(separator: "\n") + "\n\(endMarker)\n"
    }

    /// Replaces the section that maps exactly `expected` with a section for `hostnames`.
    ///
    /// An empty `expected` means "no section"; an empty `hostnames` removes the section.
    /// - Throws: `.invalid` when the file has invalid markers, an untracked or changed section,
    ///   a missing section, or an external mapping of a new hostname. The file is never changed here.
    public static func replacing(
        in data: Data, with hostnames: [Hostname], expecting expected: [Hostname]
    ) throws
        -> Data
    {
        let layout = try HostsSectionLayout.parse(data)
        try requireTracked(layout, expected: expected)
        let outsideText = layout.outsideText
        for host in hostnames.sorted() where HostsMapping.hasMapping(of: host.value, in: outsideText) {
            throw JerdError.invalid("The hostname \(host.value) already has an external hosts mapping.")
        }
        let block = Array(render(hostnames).utf8)
        guard let range = layout.section?.range else { return Data(layout.bytes + block) }
        var result = layout.bytes
        result.replaceSubrange(range, with: block)
        return Data(result)
    }

    /// Replaces the section of a committed setup that recorded `recorded`.
    ///
    /// A missing section counts as removed by another tool: nothing outside the section is changed,
    /// and a new section is added only after the external-mapping check. Without
    /// this, a deleted section blocked both removal and a new configure, and left the CA trusted.
    static func replacing(in data: Data, with hostnames: [Hostname], recorded: [Hostname]) throws -> Data {
        let layout = try HostsSectionLayout.parse(data)
        let expected = layout.section == nil && !layout.markersReversed ? [] : recorded
        return try replacing(in: data, with: hostnames, expecting: expected)
    }

    /// True when the file is valid, its section maps exactly `hostnames` (no section for an empty
    /// list), and no line outside the section maps one of them.
    public static func maps(_ hostnames: [Hostname], in data: Data) -> Bool {
        do {
            _ = try replacing(in: data, with: hostnames, expecting: hostnames)
            return true
        } catch {
            return false
        }
    }

    /// True when the file is valid and its section maps exactly `hostnames` (no section for an empty
    /// list). Unlike `maps`, a line outside the section that maps one of them does not matter.
    static func tracks(_ hostnames: [Hostname], in data: Data) -> Bool {
        do {
            try requireTracked(try HostsSectionLayout.parse(data), expected: hostnames)
            return true
        } catch {
            return false
        }
    }

    private static func requireTracked(_ layout: HostsSectionLayout, expected: [Hostname]) throws {
        if layout.markersReversed { throw untracked }
        guard let section = layout.section else {
            guard expected.isEmpty else {
                throw JerdError.invalid("The tracked Jerd hosts section is missing. No external content was changed.")
            }
            return
        }
        guard !expected.isEmpty else { throw untracked }
        guard section.mappedNames == Set(expected).sorted().map(\.value) else {
            throw JerdError.invalid("The Jerd hosts section changed outside the app. It was not overwritten.")
        }
    }

    private static let untracked = JerdError.invalid(
        "An untracked Jerd hosts section already exists. It was not changed.")
}
