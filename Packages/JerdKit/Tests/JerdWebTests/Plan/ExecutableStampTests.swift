import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdWeb

@Suite struct ExecutableStampTests {
    @Test func anUnchangedExecutableKeepsItsStampAndATouchChangesIt() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let binary = folder.path("binary")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binary)
        let first = try ExecutableStamp(path: binary.path)
        #expect(try ExecutableStamp(path: binary.path) == first)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 5)], ofItemAtPath: binary.path)
        #expect(try ExecutableStamp(path: binary.path) != first)
    }

    @Test func aReplacedExecutableGetsANewStamp() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let binary = folder.path("binary")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binary)
        let first = try ExecutableStamp(path: binary.path)
        try FileManager.default.removeItem(at: binary)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binary)
        #expect(try ExecutableStamp(path: binary.path) != first)
    }

    @Test func missingFoldersAndNonExecutableFilesAreUnavailable() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let plain = try folder.file("plain", "x")
        for path in [folder.path("missing").path, folder.url.path, plain.path] {
            #expect(throws: JerdError.unavailable("A selected runtime executable is unavailable: \(path)")) {
                try ExecutableStamp(path: path)
            }
        }
    }

    @Test func captureStampsEveryPath() throws {
        let stamps = try ExecutableStamp.capture(["/usr/bin/true", "/usr/bin/false"])
        #expect(Set(stamps.keys) == ["/usr/bin/true", "/usr/bin/false"])
    }
}
