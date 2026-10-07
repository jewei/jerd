import Darwin
import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@Suite struct InstanceLockTests {
    private let messages = InstanceLock.Messages(
        unavailable: "Cannot lock the mail inbox.", busy: "Another Jerd process is using this mail inbox.")

    @Test func aSecondAcquisitionFailsUntilTheFirstIsReleased() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("service.lock")
        let first = try InstanceLock.acquire(at: file, messages: messages)
        #expect(first.isHeld)
        #expect(throws: JerdError.locked("Another Jerd process is using this mail inbox.")) {
            try InstanceLock.acquire(at: file, messages: messages)
        }
        first.release()
        first.release()
        #expect(!first.isHeld)
        let second = try InstanceLock.acquire(at: file, messages: messages)
        #expect(second.isHeld)
        #expect(permissions(file) == 0o600)
    }

    @Test func deinitReleasesTheLock() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("service.lock")
        do { _ = try InstanceLock.acquire(at: file, messages: messages) }
        let again = try InstanceLock.acquire(at: file, messages: messages)
        #expect(again.isHeld)
    }

    @Test func aLockHeldByAnotherDescriptorBlocksAcquisition() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("service.lock")
        let other = open(file.path, O_RDWR | O_CREAT, 0o600)
        defer { close(other) }
        #expect(flock(other, LOCK_EX | LOCK_NB) == 0)
        #expect(throws: JerdError.locked(messages.busy)) { try InstanceLock.acquire(at: file, messages: messages) }
    }

    @Test func aLinkedOrMissingFolderIsUnavailable() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let target = folder.path("target")
        try Data().write(to: target)
        let link = folder.path("service.lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: JerdError.unavailable(messages.unavailable)) {
            try InstanceLock.acquire(at: link, messages: messages)
        }
        #expect(throws: JerdError.unavailable(messages.unavailable)) {
            try InstanceLock.acquire(at: folder.path("missing/service.lock"), messages: messages)
        }
    }

    @Test func guardsMatchesOnlyItsOwnFileWhileHeld() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("service.lock")
        let lock = try InstanceLock.acquire(at: file, messages: messages)
        #expect(lock.guards(folder.url.appendingPathComponent("./service.lock")))
        #expect(!lock.guards(folder.path("recovery.lock")))
        lock.release()
        #expect(!lock.guards(file))
    }
}
