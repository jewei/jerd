import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import Testing

@Suite struct ProcessLogFileTests {
    @Test func trimKeepsTheTailOnTheSameInodeForALiveWriter() throws {
        let folder = try TemporaryDirectory(" bounded log")
        defer { folder.remove() }
        let log = ProcessLogFile(url: folder.path("server.log"), threshold: 1_000)
        try AtomicFile.write(Data(repeating: 65, count: 2_000) + Data("end".utf8), to: log.url)
        let writer = try FileHandle(forWritingTo: log.url)
        defer { try? writer.close() }
        #expect(try log.trim())
        try writer.seekToEnd()
        try writer.write(contentsOf: Data("-new".utf8))
        let data = try #require(contents(log.url))
        #expect(data.count == ProcessLogFile.marker.utf8.count + 500 + 4)
        #expect(String(decoding: data, as: UTF8.self).hasPrefix(ProcessLogFile.marker))
        #expect(String(decoding: data, as: UTF8.self).hasSuffix("end-new"))
    }

    @Test func trimKeepsTheRequestedHeadBeforeTheMarker() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let log = ProcessLogFile(url: folder.path("command.log"), retainedHeadBytes: 10_000, threshold: 1_000)
        #expect(log.retainedHeadBytes == 250)
        try AtomicFile.write(Data("first".utf8) + Data(repeating: 66, count: 2_000) + Data("last".utf8), to: log.url)
        #expect(try log.trim())
        let result = text(log.url)
        #expect(result.hasPrefix("first"))
        #expect(result.contains(ProcessLogFile.marker))
        #expect(result.hasSuffix("last"))
        #expect(result.utf8.count == 250 + ProcessLogFile.marker.utf8.count + 500)
    }

    @Test func aSmallOrMissingLogIsNotChanged() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let log = ProcessLogFile(url: folder.path("server.log"), threshold: 1_000)
        #expect(try !log.trim())
        try AtomicFile.write(Data(repeating: 65, count: 1_000), to: log.url)
        #expect(try !log.trim())
        #expect(contents(log.url)?.count == 1_000)
    }

    @Test func aLinkedOrHardLinkedLogIsRefusedForTrimAndRead() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let target = folder.path("target")
        try Data(repeating: 65, count: 2_000).write(to: target)
        let linked = ProcessLogFile(url: folder.path("linked.log"), threshold: 1_000)
        try FileManager.default.createSymbolicLink(at: linked.url, withDestinationURL: target)
        #expect(throws: JerdError.invalid("The process log is not an owned regular file: \(linked.url.path)")) {
            try linked.trim()
        }
        #expect(throws: JerdError.self) { try linked.readTail(limit: 10) }
        #expect(contents(target)?.count == 2_000)
        let hard = ProcessLogFile(url: folder.path("hard.log"), threshold: 1_000)
        #expect(link(target.path, hard.url.path) == 0)
        #expect(throws: JerdError.self) { try hard.trim() }
    }

    @Test func headAndTailReadsAreBoundedAndDecodeInvalidBytes() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let log = ProcessLogFile(url: folder.path("server.log"))
        try AtomicFile.write(Data("start-".utf8) + Data([0xFF]) + Data("-end".utf8), to: log.url)
        #expect(try log.readHead(limit: 5) == "start")
        #expect(try log.readTail(limit: 4) == "-end")
        #expect(try log.readTail(limit: 1_000) == "start-\u{FFFD}-end")
        #expect(try ProcessLogFile(url: folder.path("missing.log")).readTail(limit: 10) == "")
    }

    @Test func createReplacesAnOldLogWithAnEmptyPrivateFile() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let log = ProcessLogFile(url: folder.path("server.log"))
        try Data("old".utf8).write(to: log.url)
        let handle = try log.create()
        try handle.write(contentsOf: Data("new".utf8))
        try handle.close()
        #expect(text(log.url) == "new")
        var info = stat()
        #expect(stat(log.url.path, &info) == 0 && info.st_mode & 0o777 == 0o600)
    }

    @Test func rotateMovesTheTrimmedLogToThePreviousFile() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let log = ProcessLogFile(url: folder.path("server.log"), threshold: 1_000)
        try AtomicFile.write(Data(repeating: 65, count: 3_000), to: log.url)
        try log.rotate(to: folder.path("server.previous.log"))
        #expect(FileProbe.presence(at: log.url) == .absent)
        #expect(contents(folder.path("server.previous.log"))?.count == 500 + ProcessLogFile.marker.utf8.count)
        try log.rotate(to: folder.path("server.previous.log"))
    }
}
