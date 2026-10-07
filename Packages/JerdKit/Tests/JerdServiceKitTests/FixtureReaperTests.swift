import Darwin
import Foundation
import JerdProcess
import JerdServiceKitTestSupport
import JerdTestSupport
import Testing

/// The guard that `TemporaryDirectory.remove()` runs: no fixture may outlive its test.
@Suite struct FixtureReaperTests {
    @Test func aFixtureThatIgnoresSIGTERMInTheTestFolderIsFoundAndKilled() async throws {
        let directory = try TemporaryDirectory(" service kit ü")
        defer { directory.remove() }
        let folder = directory.path("instance ü")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let supervisor = ProcessSupervisor()
        let request = ProcessRequest(
            executable: try await Fixtures.shared.executable("graceful-process"), workingDirectory: folder)
        let token = try await supervisor.start(request, log: ProcessLogFile(url: folder.appending(path: "log")))
        let pid = try #require(await supervisor.processID(of: token))
        #expect(await eventually { text(folder.appending(path: "log")) == "ready\n" })
        #expect(FixtureReaper.processes(in: try #require(realPath(directory.url))) == [pid])
        #expect(FixtureReaper.reap(in: directory.url, grace: .milliseconds(50)) == [pid])
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(5)) == .signalled(signal: SIGKILL))
        #expect(FixtureReaper.reap(in: directory.url, grace: .zero).isEmpty)
    }

    @Test func aFolderWithoutProcessesReturnsAtOnce() throws {
        let directory = try TemporaryDirectory(" service kit ü")
        defer { directory.remove() }
        let started = ContinuousClock.now
        #expect(FixtureReaper.reap(in: directory.url).isEmpty)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    private func realPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
