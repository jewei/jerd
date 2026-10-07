import Foundation
import JerdFoundation
import JerdTestSupport
import JerdTunnels
import Testing

@Suite struct ConnectorLogHistoryTests {
    private func prepared() throws -> (TemporaryDirectory, ConnectorLogHistory) {
        let folder = try TemporaryDirectory(" tunnels")
        let instance = folder.layout.instance(UUID())
        try OwnedDirectory.create(instance.root)
        return (folder, ConnectorLogHistory(instance: instance))
    }

    @Test func noLogFilesMeanNoHistory() throws {
        let (folder, history) = try prepared()
        defer { folder.remove() }
        #expect(try history.recent(limit: 100) == nil)
        try history.archiveCurrent()
        #expect(FileProbe.presence(at: history.previous.url) == .absent)
    }

    @Test func eachArchivedRunEndsWithTheBoundaryAndTheCurrentLogEmpties() throws {
        let (folder, history) = try prepared()
        defer { folder.remove() }
        try AtomicFile.write(Data("run one".utf8), to: history.current.url)
        try history.archiveCurrent()
        try AtomicFile.write(Data("run two\n".utf8), to: history.current.url)
        try history.archiveCurrent()
        let boundary = ConnectorLogHistory.boundary
        #expect(text(history.previous.url) == "run one\n\(boundary)run two\n\(boundary)")
        #expect(text(history.current.url).isEmpty)
        try history.archiveCurrent()
        #expect(text(history.previous.url) == "run one\n\(boundary)run two\n\(boundary)")
    }

    @Test func theViewShowsTheTailOfHistoryAndCurrentRun() throws {
        let (folder, history) = try prepared()
        defer { folder.remove() }
        try AtomicFile.write(Data("old\n".utf8), to: history.previous.url)
        try AtomicFile.write(Data("new\n".utf8), to: history.current.url)
        #expect(try history.recent(limit: 100) == "old\nnew\n")
        #expect(try history.recent(limit: 6) == "d\nnew\n")
    }

    @Test func theHistoryStaysBounded() throws {
        let (folder, history) = try prepared()
        defer { folder.remove() }
        let large = String(repeating: "x", count: ConnectorLogHistory.retainedBytes)
        try AtomicFile.write(Data(large.utf8), to: history.previous.url)
        try AtomicFile.write(Data("latest\n".utf8), to: history.current.url)
        try history.archiveCurrent()
        let kept = text(history.previous.url)
        #expect(kept.utf8.count == ConnectorLogHistory.retainedBytes)
        #expect(kept.hasSuffix("latest\n\(ConnectorLogHistory.boundary)"))
    }
}
