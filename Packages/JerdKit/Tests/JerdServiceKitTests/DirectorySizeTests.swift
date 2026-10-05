import Foundation
import JerdFoundation
import JerdServiceKit
import Testing

@Suite struct DirectorySizeTests {
    @Test func theSizeCountsRegularFilesAndNeverFollowsLinks() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try write("12345", to: directory.path("tree/a"))
        try write("123", to: directory.path("tree/sub/b"))
        try write(String(repeating: "x", count: 1_000), to: directory.path("outside/big"))
        try FileManager.default.createSymbolicLink(
            at: directory.path("tree/link"), withDestinationURL: directory.path("outside"))
        #expect(try await DirectorySize.bytes(in: directory.path("tree")) == 8)
    }

    @Test func aTreeAboveTheEntryLimitHasNoSize() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        for index in 0..<4 { try write("x", to: directory.path("tree/\(index)")) }
        await #expect(throws: JerdError.self) {
            _ = try await DirectorySize.bytes(in: directory.path("tree"), entryLimit: 3)
        }
    }

    @Test func aCancelledSizeCheckStops() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try write("x", to: directory.path("tree/a"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DirectorySize.bytes(in: directory.path("tree"))
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
