import Darwin
import Foundation
import os

/// An exclusive, non-blocking advisory `flock` on a lock file. It is released by `release()` or deinit.
///
/// A second acquisition of the same file fails, also inside one process, because `flock`
/// belongs to each open file description. Old and new Jerd builds use the same lock file
/// names, so they exclude each other.
public final class InstanceLock: Sendable {
    /// The user messages for the two ways an acquisition can fail.
    public struct Messages: Sendable, Equatable {
        /// Shown when the lock file cannot be opened or is not a private regular file.
        public let unavailable: String
        /// Shown when another owner holds the lock.
        public let busy: String

        public init(unavailable: String, busy: String) {
            self.unavailable = unavailable
            self.busy = busy
        }
    }

    /// The lock file.
    public let url: URL
    private let descriptor: OSAllocatedUnfairLock<Int32?>

    private init(url: URL, descriptor: Int32) {
        self.url = url
        self.descriptor = OSAllocatedUnfairLock(initialState: descriptor)
    }

    deinit { release() }

    /// Opens (and creates, mode 0600) the lock file and takes the lock without waiting.
    /// - Throws: `.unavailable(messages.unavailable)` or `.locked(messages.busy)`.
    public static func acquire(at url: URL, messages: Messages) throws -> InstanceLock {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, AtomicFile.fileMode)
        guard descriptor >= 0 else { throw JerdError.unavailable(messages.unavailable) }
        guard let info = DescriptorIO.status(of: descriptor), DescriptorIO.isPrivateRegularFile(info, owner: geteuid())
        else {
            close(descriptor)
            throw JerdError.unavailable(messages.unavailable)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw JerdError.locked(messages.busy)
        }
        return InstanceLock(url: url, descriptor: descriptor)
    }

    /// True until `release()` runs.
    public var isHeld: Bool { descriptor.withLock { $0 != nil } }

    /// True when this lock is held and guards `file` (paths compared after removing `.` and `..`).
    public func guards(_ file: URL) -> Bool {
        isHeld && url.standardizedFileURL.path == file.standardizedFileURL.path
    }

    /// Unlocks and closes the lock file. Later calls do nothing.
    public func release() {
        descriptor.withLock { value in
            guard let open = value else { return }
            _ = flock(open, LOCK_UN)
            close(open)
            value = nil
        }
    }
}
