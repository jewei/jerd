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
}
