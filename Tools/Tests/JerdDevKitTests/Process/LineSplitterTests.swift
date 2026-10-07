import Foundation
import Testing

@testable import JerdDevKit

@Suite("Line splitter")
struct LineSplitterTests {
    @Test("returns only complete lines and keeps the rest")
    func returnsCompleteLines() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("one\ntw".utf8)) == ["one"])
        #expect(splitter.append(Data("o\nthree".utf8)) == ["two"])
        #expect(splitter.finish() == "three")
        #expect(splitter.finish() == nil)
    }

    @Test("keeps empty lines")
    func keepsEmptyLines() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("a\n\nb\n".utf8)) == ["a", "", "b"])
        #expect(splitter.finish() == nil)
    }

    @Test("joins a UTF-8 character that arrives in two parts")
    func joinsSplitCharacters() {
        var splitter = LineSplitter()
        let bytes = Array("é\n".utf8)
        #expect(splitter.append(Data(bytes[0..<1])).isEmpty)
        #expect(splitter.append(Data(bytes[1...])) == ["é"])
    }

    @Test("splits many lines in many chunks, and a long line that arrives in parts")
    func splitsLargeInput() {
        var splitter = LineSplitter()
        var lines: [String] = []
        let chunk = Data(String(repeating: "0123456789\n", count: 6_000).utf8)
        for _ in 0..<32 {
            lines += splitter.append(chunk)
        }
        #expect(lines.count == 192_000)
        #expect(lines.allSatisfy { $0 == "0123456789" })
        let longLine = String(repeating: "x", count: 100_000)
        for part in stride(from: 0, to: longLine.count, by: 1_000) {
            #expect(splitter.append(Data(longLine.utf8.dropFirst(part).prefix(1_000))).isEmpty)
        }
        #expect(splitter.append(Data("\n".utf8)) == [longLine])
    }
}
