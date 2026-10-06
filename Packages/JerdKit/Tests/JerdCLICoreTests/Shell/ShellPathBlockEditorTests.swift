import JerdFoundation
import Testing

@testable import JerdCLICore

@Suite struct ShellPathBlockEditorTests {
    private static let block = ShellPathBlockEditor.block
    private static let start = ShellPathBlockEditor.startMarker
    private static let end = ShellPathBlockEditor.endMarker
    private static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    private static func apply(_ text: String) throws -> String {
        String(decoding: try ShellPathBlockEditor.apply(to: Array(text.utf8)), as: UTF8.self)
    }

    private static func apply(_ bytes: [UInt8]) throws -> [UInt8] { try ShellPathBlockEditor.apply(to: bytes) }

    @Test func blockIsTheCompatibleText() {
        #expect(
            Self.block
                == "# >>> Jerd PHP CLI >>>\nexport PATH=\"$HOME/Library/Application Support/Jerd/bin:$PATH\"\n"
                + "# <<< Jerd PHP CLI <<<\n")
    }

    private static let appendCases: [(String, String)] = [
        ("", block),
        ("export EDITOR=vi\n", "export EDITOR=vi\n\n" + block),
        ("export EDITOR=vi", "export EDITOR=vi\n\n" + block),
        ("export EDITOR=vi\n\n", "export EDITOR=vi\n\n" + block),
        ("export EDITOR=vi\n\n\n", "export EDITOR=vi\n\n\n" + block),
    ]

    private static let idempotenceCases: [String] = [
        "a\n\n" + block,
        block,
        "a\n" + block + "\n\nb\n",
        "a\n" + start + "\nexport PATH=/old:$PATH\n" + end + "\nb\n",
        start + "\n" + end,
    ]

    private static let malformedCases: [String] = [
        start + "\n",
        end + "\n",
        end + "\n" + start + "\n",
        block + block,
        start + "\n" + start + "\n" + end + "\n",
        "echo '" + start + "'\n" + end + "\n",
    ]

    @Test(arguments: appendCases)
    func absentBlockIsAppendedAfterTheUnchangedUserText(original: String, expected: String) throws {
        #expect(try Self.apply(original) == expected)
        #expect(try Self.apply(original).hasPrefix(original))
    }

    @Test(arguments: idempotenceCases)
    func applyingTwiceGivesTheSameText(original: String) throws {
        let once = try Self.apply(original)
        #expect(try Self.apply(once) == once)
    }

    @Test func oldBlockIsReplacedInPlaceAndUserLinesAroundItStay() throws {
        let original = "a\n" + Self.start + "\nexport PATH=/old:$PATH\n" + Self.end + "\n\n\nb\n"
        #expect(try Self.apply(original) == "a\n" + Self.block + "\n\nb\n")
    }

    @Test func blockAtTheEndWithoutLineEndGetsOne() throws {
        let original = "a\n" + Self.block.dropLast()
        #expect(try Self.apply(original) == "a\n" + Self.block)
    }

    @Test(arguments: malformedCases)
    func malformedMarkersAreRefused(text: String) {
        #expect(ShellPathBlockEditor.state(of: Array(text.utf8)) == .malformed)
        #expect(throws: JerdError.invalid("The Jerd PATH block needs manual review.")) {
            try Self.apply(text)
        }
    }

    @Test func stateGivesTheByteRangeOfTheBlock() {
        let text = "é\n" + Self.block + "z"
        let start = "é\n".utf8.count
        #expect(ShellPathBlockEditor.state(of: Array(text.utf8)) == .present(start..<(start + Self.block.utf8.count)))
        #expect(ShellPathBlockEditor.state(of: Array("plain".utf8)) == .absent)
    }

    private static let lineEndCases: [(String, String)] = [
        ("export A=1\r\n", "export A=1\r\n\r\n" + block),
        ("export A=1\r\n\r\n", "export A=1\r\n\r\n" + block),
        ("export A=1\r\nexport B=2", "export A=1\r\nexport B=2\r\n\r\n" + block),
        ("a\r\n" + start + "\r\nexport PATH=/old:$PATH\r\n" + end + "\r\nb\r\n", "a\r\n" + block + "b\r\n"),
    ]

    /// A CRLF file gets one blank line in its own style, and its bytes stay.
    @Test(arguments: lineEndCases)
    func crlfFilesKeepTheirLineEnds(original: String, expected: String) throws {
        #expect(try Self.apply(original) == expected)
        #expect(try Self.apply(expected) == expected)
    }

    /// A byte order mark stays, and a file with the exact block does not change.
    @Test func byteOrderMarkStays() throws {
        let original = Self.bom + Array("export A=1\n".utf8)
        let once = try Self.apply(original)
        #expect(once == original + Array("\n".utf8) + Array(Self.block.utf8))
        #expect(try Self.apply(once) == once)
        let blockFirst = Self.bom + Array(Self.block.utf8)
        #expect(ShellPathBlockEditor.state(of: blockFirst) == .present(3..<(3 + Self.block.utf8.count)))
        #expect(try Self.apply(blockFirst) == blockFirst)
    }
}
