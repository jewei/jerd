import JerdFoundation
import Testing

@testable import JerdCLICore

@Suite struct ShellPathBlockEditorTests {
    private static let block = ShellPathBlockEditor.block
    private static let start = ShellPathBlockEditor.startMarker
    private static let end = ShellPathBlockEditor.endMarker

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
        #expect(try ShellPathBlockEditor.apply(to: original) == expected)
        #expect(try ShellPathBlockEditor.apply(to: original).hasPrefix(original))
    }

    @Test(arguments: idempotenceCases)
    func applyingTwiceGivesTheSameText(original: String) throws {
        let once = try ShellPathBlockEditor.apply(to: original)
        #expect(try ShellPathBlockEditor.apply(to: once) == once)
    }

    @Test func oldBlockIsReplacedInPlaceAndUserLinesAroundItStay() throws {
        let original = "a\n" + Self.start + "\nexport PATH=/old:$PATH\n" + Self.end + "\n\n\nb\n"
        #expect(try ShellPathBlockEditor.apply(to: original) == "a\n" + Self.block + "\n\nb\n")
    }

    @Test func blockAtTheEndWithoutLineEndGetsOne() throws {
        let original = "a\n" + Self.block.dropLast()
        #expect(try ShellPathBlockEditor.apply(to: original) == "a\n" + Self.block)
    }

    @Test(arguments: malformedCases)
    func malformedMarkersAreRefused(text: String) {
        #expect(ShellPathBlockEditor.state(of: text) == .malformed)
        #expect(throws: JerdError.invalid("The Jerd PATH block needs manual review.")) {
            try ShellPathBlockEditor.apply(to: text)
        }
    }

    @Test func stateGivesTheByteRangeOfTheBlock() {
        let text = "é\n" + Self.block + "z"
        let start = "é\n".utf8.count
        #expect(ShellPathBlockEditor.state(of: text) == .present(start..<(start + Self.block.utf8.count)))
        #expect(ShellPathBlockEditor.state(of: "plain") == .absent)
    }
}
