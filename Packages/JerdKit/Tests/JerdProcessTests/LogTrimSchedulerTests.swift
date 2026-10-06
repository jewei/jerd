import Foundation
import JerdFoundation
import Testing

@testable import JerdProcess

@Suite struct LogTrimSchedulerTests {
    @Test func registeredLogsAreTrimmedPeriodicallyAndOnceMoreWhenRemoved() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let log = ProcessLogFile(url: folder.path("server.log"), threshold: 1_000)
        try AtomicFile.write(Data(), to: log.url)
        let scheduler = LogTrimScheduler(interval: .milliseconds(10))
        await scheduler.register(log)
        #expect(await scheduler.isRunning)
        try Data(repeating: 65, count: 5_000).write(to: log.url)
        #expect(await eventually { (contents(log.url)?.count ?? 0) < 1_000 })
        try Data(repeating: 66, count: 5_000).write(to: log.url)
        await scheduler.unregister(log)
        #expect((contents(log.url)?.count ?? 0) < 1_000)
        #expect(await !scheduler.isRunning)
    }

    @Test func aFailedTrimIsKeptForInspection() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try Data(repeating: 65, count: 2_000).write(to: folder.path("target"))
        let log = ProcessLogFile(url: folder.path("server.log"), threshold: 1_000)
        try FileManager.default.createSymbolicLink(at: log.url, withDestinationURL: folder.path("target"))
        let scheduler = LogTrimScheduler(interval: .milliseconds(10))
        await scheduler.register(log)
        #expect(await eventually { await scheduler.failure(for: log.url) != nil })
        #expect(
            await scheduler.failure(for: log.url) == "The process log is not an owned regular file: \(log.url.path)")
        // Fixed review L6: removal returns the last failure and forgets it.
        #expect(await scheduler.unregister(log) == "The process log is not an owned regular file: \(log.url.path)")
        #expect(await scheduler.failure(for: log.url) == nil)
    }
}
