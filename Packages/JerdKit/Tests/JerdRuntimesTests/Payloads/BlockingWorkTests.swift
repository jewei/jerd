import Foundation
import JerdArchive
import JerdFoundation
import JerdRuntimes
import Testing
import os

@Suite struct BlockingWorkTests {
    /// Waits inside the blocking work until it sees the cancellation of its task, for at most 5 seconds.
    private static func waitForCancellation(_ started: OSAllocatedUnfairLock<Bool>) {
        started.withLock { $0 = true }
        let deadline = Date().addingTimeInterval(5)
        while !Task.isCancelled, Date() < deadline { usleep(1_000) }
    }

    private static func waitUntilStarted(_ started: OSAllocatedUnfairLock<Bool>) async throws {
        while !started.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(1)) }
    }

    @Test func runningWorkSeesTheCancellationOfItsTask() async throws {
        let started = OSAllocatedUnfairLock(initialState: false)
        let task = Task {
            try await BlockingWork.run {
                Self.waitForCancellation(started)
                return Task.isCancelled
            }
        }
        try await Self.waitUntilStarted(started)
        task.cancel()
        #expect(try await task.value)
    }

    @Test func runningDigestStopsAtTheNextChunk() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let file = folder.path("download")
        try makeSparseFile(file, size: off_t(FileDigest.chunkSize * 4))
        let started = OSAllocatedUnfairLock(initialState: false)
        let task = Task {
            try await BlockingWork.run {
                Self.waitForCancellation(started)
                return try FileDigest.hexSHA256(of: file)
            }
        }
        try await Self.waitUntilStarted(started)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func runningExtractionStopsBeforeTheNextEntry() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("first", "one")
        tar.file("second", "two")
        let archive = folder.path("archive.tar")
        try tar.data.write(to: archive)
        let output = folder.path("output")
        try OwnedDirectory.create(output)
        let started = OSAllocatedUnfairLock(initialState: false)
        let task = Task {
            try await BlockingWork.run {
                Self.waitForCancellation(started)
                return try ArchiveExtractor.extract(archive, to: output, policy: ExtractionPolicy { _ in true })
            }
        }
        try await Self.waitUntilStarted(started)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }

    @Test func cancelledTaskDoesNotStartTheWork() async throws {
        let ran = OSAllocatedUnfairLock(initialState: false)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await BlockingWork.run { ran.withLock { $0 = true } }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!ran.withLock { $0 })
    }
}
