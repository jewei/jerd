import Darwin
import Foundation
import JerdFoundation

/// Replaces a root-owned file (the hosts file) only while it still holds the expected bytes.
///
/// The steps: open without following links, take an advisory lock without blocking (retry until a
/// deadline), compare the bytes, stage the new bytes beside the file, copy owner, group, mode, ACL,
/// extended attributes, and flags (the modification time becomes "now", so resolvers see the edit),
/// check that nothing changed, exchange the two files with `renamex_np(RENAME_SWAP)`, and verify
/// the displaced file. When another writer raced the exchange, the swap is undone only when that is
/// safe. A staging file stays on disk only with a `.partialChange` error that names its path.
/// No path comes from XPC: the helper supplies `/private/etc/hosts`.
public struct GuardedFileSwap: HostsFileAccessing {
    /// The largest file and replacement (bytes).
    public static let maximumSize = 1_048_576
    /// How long `replace` waits for another holder of the advisory lock.
    public static let defaultLockTimeout: Duration = .seconds(5)

    public let url: URL
    public let expectedOwner: uid_t
    public let lockTimeout: Duration
    let hooks: GuardedFileSwapHooks

    public init(url: URL, expectedOwner: uid_t, lockTimeout: Duration = Self.defaultLockTimeout) {
        self.init(url: url, expectedOwner: expectedOwner, lockTimeout: lockTimeout, hooks: GuardedFileSwapHooks())
    }

    /// Test seam: the hooks run just before the exchange and just before an undo exchange.
    package init(url: URL, expectedOwner: uid_t, lockTimeout: Duration, hooks: GuardedFileSwapHooks) {
        self.url = url
        self.expectedOwner = expectedOwner
        self.lockTimeout = lockTimeout
        self.hooks = hooks
    }

    public func read() throws -> Data {
        let descriptor = try openChecked(url)
        defer { close(descriptor) }
        return try bytes(descriptor)
    }

    public func replace(expected: Data, with replacement: Data) async throws {
        guard replacement.count <= Self.maximumSize else { throw JerdError.invalid("The hosts update is too large.") }
        let source = try openChecked(url)
        defer { close(source) }
        try await lock(source)
        defer { flock(source, LOCK_UN) }
        guard try bytes(source) == expected else { throw JerdError.invalid("The hosts file changed. Retry the setup.") }
        let original = try FileMetadataSnapshot.capture(source)
        let stage = try StagingFile(beside: url)
        defer { stage.finish() }
        try stage.write(replacement, metadataFrom: source)
        try requireUnchanged(source, original: original, expected: expected)
        let staged = try FileMetadataSnapshot.capture(stage.descriptor)
        try hooks.beforeExchange()
        try commit(stage, original: original, staged: staged, expected: expected, replacement: replacement)
    }

    /// Exchanges the files, then verifies that the displaced file is the one that was checked.
    private func commit(
        _ stage: StagingFile, original: FileMetadataSnapshot, staged: FileMetadataSnapshot, expected: Data,
        replacement: Data
    ) throws {
        guard renamex_np(stage.url.path, url.path, UInt32(RENAME_SWAP)) == 0 else {
            throw JerdError.invalid("Cannot commit the hosts update.")
        }
        stage.holdsDisplacedFile = true
        defer { syncDirectory() }
        if matches(stage.url, metadata: original, content: expected) {
            stage.holdsDisplacedFile = false
            return
        }
        try undo(stage, staged: staged, replacement: replacement)
    }

    /// Another writer replaced the file before the exchange. Put its file back, but never replace a
    /// file that a third writer placed later.
    private func undo(_ stage: StagingFile, staged: FileMetadataSnapshot, replacement: Data) throws {
        let recovery = JerdError.partialChange(
            "The hosts file changed during setup. A displaced file is preserved at \(stage.url.path). "
                + "Inspect it before recovery.")
        guard matches(url, metadata: staged, content: replacement) else { throw recovery }
        do { try hooks.beforeUndo() } catch { throw recovery }
        guard renamex_np(stage.url.path, url.path, UInt32(RENAME_SWAP)) == 0,
            matches(stage.url, metadata: staged, content: replacement)
        else { throw recovery }
        stage.holdsDisplacedFile = false
        throw JerdError.invalid("The hosts file changed during setup. Retry the operation.")
    }

    private func requireUnchanged(_ source: Int32, original: FileMetadataSnapshot, expected: Data) throws {
        var current = stat()
        guard lstat(url.path, &current) == 0, current.st_dev == original.info.st_dev,
            current.st_ino == original.info.st_ino,
            try FileMetadataSnapshot.capture(source).matches(original, includingChangeTime: true),
            try bytes(source) == expected
        else { throw JerdError.invalid("The hosts file changed during setup. Retry the operation.") }
    }

    private func syncDirectory() {
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
        guard directory >= 0 else { return }
        _ = fsync(directory)
        close(directory)
    }
}
