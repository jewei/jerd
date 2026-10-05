import Foundation
import JerdFoundation

/// A hosts file split into the bytes outside Jerd's tracked section and the section itself.
///
/// Lines end at LF. A marker is a full line, `# BEGIN JERD` or `# END JERD`, with an optional CR.
/// The section range starts at the BEGIN line (plus one LF before it) and ends after the END line
/// (plus its LF). Removing that range from a file that Jerd extended gives back the original bytes.
struct HostsSectionLayout: Sendable {
    /// One found section.
    struct Section: Sendable {
        /// The bytes to remove or replace.
        let range: Range<Int>
        /// The body lines between the markers, in file order, or nil when a line is not
        /// `127.0.0.1 <name>` (whitespace and a CR around the fields are allowed, empty lines are ignored).
        let mappedNames: [String]?
    }

    let bytes: [UInt8]
    let section: Section?
    /// True when a BEGIN marker comes after the END marker.
    let markersReversed: Bool

    /// Parses `data`. Throws when the file is too large, not UTF-8, or has unpaired or repeated markers.
    static func parse(_ data: Data) throws -> HostsSectionLayout {
        guard data.count <= HostsSection.maximumSize, String(data: data, encoding: .utf8) != nil else {
            throw JerdError.invalid("The hosts file is too large or is not valid UTF-8. It was not changed.")
        }
        let bytes = [UInt8](data)
        let lines = lineRanges(bytes)
        let begins = lines.filter { isMarker(bytes[$0], HostsSection.beginMarker) }
        let ends = lines.filter { isMarker(bytes[$0], HostsSection.endMarker) }
        guard begins.count == ends.count, begins.count <= 1 else {
            throw JerdError.invalid("The Jerd hosts section has invalid markers. The hosts file was not changed.")
        }
        guard let begin = begins.first, let end = ends.first else {
            return HostsSectionLayout(bytes: bytes, section: nil, markersReversed: false)
        }
        guard begin.upperBound < end.lowerBound else {
            return HostsSectionLayout(bytes: bytes, section: nil, markersReversed: true)
        }
        let body = lines.filter { $0.lowerBound > begin.upperBound && $0.upperBound < end.lowerBound }
        let start =
            begin.lowerBound > 0 && bytes[begin.lowerBound - 1] == lineFeed ? begin.lowerBound - 1 : begin.lowerBound
        let finish = end.upperBound < bytes.count ? end.upperBound + 1 : end.upperBound
        let section = Section(range: start..<finish, mappedNames: mappedNames(body.map { bytes[$0] }))
        return HostsSectionLayout(bytes: bytes, section: section, markersReversed: false)
    }

    /// The file without the section.
    var outside: [UInt8] {
        guard let section else { return bytes }
        return Array(bytes[..<section.range.lowerBound] + bytes[section.range.upperBound...])
    }

    private static let lineFeed: UInt8 = 0x0A

    /// The range of each line without its LF.
    private static func lineRanges(_ bytes: [UInt8]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        for (index, byte) in bytes.enumerated() where byte == lineFeed {
            ranges.append(start..<index)
            start = index + 1
        }
        if start < bytes.count { ranges.append(start..<bytes.count) }
        return ranges
    }

    private static func isMarker(_ line: ArraySlice<UInt8>, _ marker: String) -> Bool {
        let content = line.last == 0x0D ? line.dropLast() : line
        return content.elementsEqual(marker.utf8)
    }

    private static func mappedNames(_ lines: [ArraySlice<UInt8>]) -> [String]? {
        var names: [String] = []
        for line in lines {
            let fields = String(decoding: line, as: UTF8.self).split(whereSeparator: \.isWhitespace)
            if fields.isEmpty { continue }
            guard fields.count == 2, fields[0] == HostsSection.address else { return nil }
            names.append(String(fields[1]))
        }
        return names
    }
}
