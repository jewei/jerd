import JerdFoundation

/// Inserts or replaces the managed PATH block in the text of a zsh startup file. Pure.
///
/// Rules:
/// - The block is exactly `block`. Its markers are a compatibility contract with older setups.
/// - Text without a marker gets the block at the end, after one blank line. The user's bytes
///   stay unchanged as the prefix.
/// - Text with one start marker at a line start, followed by one end marker, gets the block in the
///   same place. Only the old block and the line end of its end marker are replaced.
/// - Any other use of a marker is malformed. The editor then refuses to change the text.
/// - Applying the editor to its own result gives the same text.
public enum ShellPathBlockEditor {
    public static let startMarker = "# >>> Jerd PHP CLI >>>"
    public static let endMarker = "# <<< Jerd PHP CLI <<<"
    public static let block =
        startMarker + "\n" + #"export PATH="$HOME/Library/Application Support/Jerd/bin:$PATH""# + "\n"
        + endMarker + "\n"

    /// The state of the managed block in a text.
    public enum BlockState: Equatable, Sendable {
        case absent
        /// One well-formed block in the UTF-8 offset range, including the line end of the end marker.
        case present(Range<Int>)
        case malformed
    }

    /// Finds the managed block in `text`.
    public static func state(of text: String) -> BlockState {
        let bytes = Array(text.utf8)
        let starts = occurrences(of: startMarker, in: bytes)
        let ends = occurrences(of: endMarker, in: bytes)
        if starts.isEmpty && ends.isEmpty { return .absent }
        guard starts.count == 1, ends.count == 1, let start = starts.first, let end = ends.first,
            start < end, start == 0 || bytes[start - 1] == UInt8(ascii: "\n")
        else { return .malformed }
        var finish = end + endMarker.utf8.count
        if finish < bytes.count, bytes[finish] == UInt8(ascii: "\n") { finish += 1 }
        return .present(start..<finish)
    }

    /// The text with the current block.
    /// - Throws: `.invalid` when the markers are malformed.
    public static func apply(to text: String) throws -> String {
        switch state(of: text) {
        case .absent:
            return text + separator(after: text) + block
        case .present(let range):
            let bytes = Array(text.utf8)
            return String(
                decoding: bytes[..<range.lowerBound] + Array(block.utf8) + bytes[range.upperBound...], as: UTF8.self)
        case .malformed:
            throw JerdError.invalid("The Jerd PATH block needs manual review.")
        }
    }

    /// One blank line between the user's text and the block, without removing any user byte.
    private static func separator(after text: String) -> String {
        if text.isEmpty || text.hasSuffix("\n\n") { return "" }
        return text.hasSuffix("\n") ? "\n" : "\n\n"
    }

    private static func occurrences(of marker: String, in bytes: [UInt8]) -> [Int] {
        let needle = Array(marker.utf8)
        guard bytes.count >= needle.count else { return [] }
        return (0...(bytes.count - needle.count)).filter { bytes[$0..<($0 + needle.count)].elementsEqual(needle) }
    }
}
