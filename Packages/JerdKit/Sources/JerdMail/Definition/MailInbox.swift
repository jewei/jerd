import Darwin
import Foundation
import JerdFoundation
import JerdServiceKit

/// The inbox folder `mail/inbox/`: the Mailpit database, its runtime identity (`runtime.json`),
/// and the marker of a successful start (`initialized.json`). Both markers hold a `MailRuntime`.
///
/// Rules:
/// - An inbox is never opened with another runtime, also not one in another folder.
/// - Files in an inbox without an identity are never adopted.
/// - After a successful start, the database must exist. A missing database is never replaced
///   with an empty one.
/// - The database is a regular file with mode 0600, never a symbolic link.
struct MailInbox: Sendable {
    let layout: MailLayout

    var identity: DataIdentityGuard<MailRuntime> {
        DataIdentityGuard(
            file: layout.runtimeIdentityFile,
            messages: .init(mismatch: MailMessages.identityMismatch, untracked: MailMessages.untracked))
    }

    var marker: InitializationMarker<MailRuntime> {
        InitializationMarker(
            file: layout.initializedMarkerFile,
            messages: .init(mismatch: MailMessages.initializedMismatch, interrupted: nil))
    }

    /// Prepares the inbox for a start with `runtime`. It creates the folder, the identity, and an
    /// empty database only for a new inbox.
    func prepare(for runtime: MailRuntime) throws {
        try OwnedDirectory.create(layout.inboxDirectory, within: layout.root)
        try requireCompleteIfInitialized(for: runtime)
        try identity.admit(runtime, dataIsUntouched: try DataFolder.isAbsentOrEmpty(layout.inboxDirectory))
        try prepareDatabase()
    }

    /// Applies the rules of `prepare(for:)` without a write, for example before a runtime update.
    func validate(for runtime: MailRuntime) throws {
        try requireCompleteIfInitialized(for: runtime)
        if let saved = try identity.saved() {
            guard saved == runtime else { throw MailMessages.identityMismatch }
        } else if !(try DataFolder.isAbsentOrEmpty(layout.inboxDirectory)) {
            throw MailMessages.untracked
        }
        if FileProbe.presence(at: layout.inboxDatabaseFile).mayExist {
            guard DataFolder.isRegularFile(layout.inboxDatabaseFile) else { throw MailMessages.databaseNotRegular }
        }
    }

    /// Moves the saved markers to `runtime` in a runtime update. Absent markers stay absent.
    func adopt(_ runtime: MailRuntime) throws {
        if try identity.saved() != nil { try MarkerFile.write(runtime, to: layout.runtimeIdentityFile) }
        if FileProbe.presence(at: layout.initializedMarkerFile).mayExist { try marker.write(runtime) }
    }

    /// Saves the marker of a successful start.
    func markInitialized(_ runtime: MailRuntime) throws {
        try marker.write(runtime)
    }

    private func requireCompleteIfInitialized(for runtime: MailRuntime) throws {
        _ = try marker.status(
            expected: runtime, dataIsComplete: DataFolder.isRegularFile(layout.inboxDatabaseFile),
            dataMayExist: false)
    }

    /// Keeps an existing database (mode 0600) or creates an empty one.
    private func prepareDatabase() throws {
        let file = layout.inboxDatabaseFile
        guard FileProbe.presence(at: file).mayExist else {
            try AtomicFile.write(Data(), to: file)
            return
        }
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw MailMessages.databaseNotRegular }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw MailMessages.databaseNotRegular
        }
        guard info.st_mode & 0o777 == AtomicFile.fileMode || fchmod(descriptor, AtomicFile.fileMode) == 0 else {
            throw JerdError.unavailable("Cannot protect the mail database (\(SystemError.describe(errno))).")
        }
    }
}
