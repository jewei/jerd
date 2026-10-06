import JerdFoundation

/// Inserts or replaces the managed PATH block in the bytes of a zsh startup file. Pure.
///
/// Rules:
/// - The block is exactly `block`, with LF line ends. Its text is a compatibility contract with
///   older setups, and a CR in it would become part of `PATH` in zsh.
/// - The editor works on bytes, so every user byte stays: a UTF-8 byte order mark, CRLF line ends,
///   and the text around the block.
/// - Text without a marker gets the block at the end, after one blank line in the file's own
///   line-end style (the style of its last line end, else of its first, else LF).
/// - Text with one start marker at a line start (the start of the text after a byte order mark
///   counts), followed by one end marker, gets the block in the same place. Only the old block
///   and the line end (LF or CRLF) of its end marker are replaced.
/// - Any other use of a marker is malformed. The editor then refuses to change the text.
/// - Applying the editor to its own result gives the same bytes.
enum ShellPathBlockEditor {
    static let startMarker = "# >>> Jerd PHP CLI >>>"
    static let endMarker = "# <<< Jerd PHP CLI <<<"
    static let block =
        startMarker + "\n" + #"export PATH="$HOME/Library/Application Support/Jerd/bin:$PATH""# + "\n"
        + endMarker + "\n"

    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// The state of the managed block in a text.
    enum BlockState: Equatable, Sendable {
        case absent
        /// One well-formed block in the byte range, including the line end of the end marker.
        case present(Range<Int>)
        case malformed
    }

    /// Finds the managed block in `bytes`.
    static func state(of bytes: [UInt8]) -> BlockState {
        let starts = occurrences(of: startMarker, in: bytes)
        let ends = occurrences(of: endMarker, in: bytes)
        if starts.isEmpty && ends.isEmpty { return .absent }
        guard starts.count == 1, ends.count == 1, let start = starts.first, let end = ends.first,
            start < end, isLineStart(start, in: bytes)
        else { return .malformed }
        var finish = end + endMarker.utf8.count
        if bytes[finish...].starts(with: [carriageReturn, lineFeed]) {
            finish += 2
        } else if bytes[finish...].first == lineFeed {
            finish += 1
        }
        return .present(start..<finish)
    }

    /// The bytes with the current block.
    /// - Throws: `.invalid` when the markers are malformed.
    static func apply(to bytes: [UInt8]) throws -> [UInt8] {
        switch state(of: bytes) {
        case .absent:
            return bytes + separator(after: bytes) + Array(block.utf8)
        case .present(let range):
            return Array(bytes[..<range.lowerBound]) + Array(block.utf8) + Array(bytes[range.upperBound...])
        case .malformed:
            throw JerdError.invalid("The Jerd PATH block needs manual review.")
        }
    }

    /// One blank line between the user's text and the block, without removing any user byte.
    private static func separator(after bytes: [UInt8]) -> [UInt8] {
        guard !bytes.isEmpty else { return [] }
        guard bytes.last == lineFeed else { return lineEnd(atFirstIn: bytes) + lineEnd(atFirstIn: bytes) }
        let style = bytes.dropLast().last == carriageReturn ? [carriageReturn, lineFeed] : [lineFeed]
        return bytes.dropLast(style.count).suffix(style.count).elementsEqual(style) ? [] : style
    }

    /// The line end of the first line, CRLF or LF; LF when the text has no line end.
    private static func lineEnd(atFirstIn bytes: [UInt8]) -> [UInt8] {
        guard let index = bytes.firstIndex(of: lineFeed), index > 0, bytes[index - 1] == carriageReturn else {
            return [lineFeed]
        }
        return [carriageReturn, lineFeed]
    }

    private static func isLineStart(_ index: Int, in bytes: [UInt8]) -> Bool {
        index == 0 || bytes[index - 1] == lineFeed
            || (index == byteOrderMark.count && bytes.starts(with: byteOrderMark))
    }

    private static func occurrences(of marker: String, in bytes: [UInt8]) -> [Int] {
        let needle = Array(marker.utf8)
        guard bytes.count >= needle.count else { return [] }
        return (0...(bytes.count - needle.count)).filter { bytes[$0..<($0 + needle.count)].elementsEqual(needle) }
    }
}
