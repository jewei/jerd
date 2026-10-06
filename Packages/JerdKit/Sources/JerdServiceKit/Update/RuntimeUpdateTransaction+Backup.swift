import Darwin
import Foundation
import JerdFoundation

extension RuntimeUpdateTransaction {
    /// Copies every existing named item to `runtime-backups/<UUID>/`, flushes the copies to the
    /// drive, then writes the journal.
    ///
    /// A crash before the journal write leaves only an unused backup folder. A journal never
    /// names a copy that a power loss can make incomplete. A symbolic link at a name, also a
    /// dangling one, stops the update.
    public func beginBackup(holding lease: MaintenanceLease) async throws -> RuntimeUpdateJournal {
        try requireLease(lease)
        guard !isPending else { throw JerdError.unavailable(Self.pendingMessage) }
        let id = UUID()
        let folder = backupsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try OwnedDirectory.create(folder, within: root)
        var present: [String] = []
        for name in names {
            let source = root.appendingPathComponent(name)
            guard FileProbe.presence(at: source).mayExist else { continue }
            try await ServiceDataCopier.copy(source, to: folder.appendingPathComponent(name))
            present.append(name)
        }
        try await flushData(present.map { folder.appendingPathComponent($0) }, [folder, backupsDirectory])
        let journal = RuntimeUpdateJournal(id: id, names: names, present: present)
        try MarkerFile.write(journal, to: journalFile)
        return journal
    }

    /// Deletes the journal. The backup folder stays.
    public func commit(holding lease: MaintenanceLease) throws {
        try requireLease(lease)
        try AtomicFile.remove(journalFile)
    }

    /// Restores the backup that the journal names. Without a journal it does nothing.
    ///
    /// Every backup tree is validated before anything moves. Current items are moved (never
    /// deleted) into `failed-attempt-<UUID>/` in the backup folder. A restore that a crash
    /// interrupts can run again: the journal stays until the restored items are flushed to the
    /// drive.
    public func restore(holding lease: MaintenanceLease) async throws {
        try requireLease(lease)
        guard isPending else { return }
        let journal = try readJournal()
        let folder = backupsDirectory.appendingPathComponent(journal.id.uuidString, isDirectory: true)
        do {
            try OwnedDirectory.requireContained(folder, in: root)
        } catch {
            throw JerdError.invalid(Self.invalidBackupMessage)
        }
        for name in journal.present { try await ServiceDataCopier.validateTree(folder.appendingPathComponent(name)) }
        let failed = folder.appendingPathComponent("failed-attempt-\(UUID().uuidString)", isDirectory: true)
        try OwnedDirectory.create(failed, within: root)
        for name in journal.names {
            let target = root.appendingPathComponent(name)
            if FileProbe.presence(at: target).mayExist {
                try move(target, to: failed.appendingPathComponent(name))
            }
            if journal.present.contains(name) {
                try await ServiceDataCopier.copy(folder.appendingPathComponent(name), to: target)
            }
        }
        try await flushData(journal.present.map { root.appendingPathComponent($0) }, [failed, root])
        try AtomicFile.remove(journalFile)
    }

    /// Reads and checks the journal. An invalid journal stays in place and protects the backups.
    func readJournal() throws -> RuntimeUpdateJournal {
        let data = try AtomicFile.read(journalFile, limit: RuntimeUpdateJournal.maximumBytes + 1)
        guard data.count <= RuntimeUpdateJournal.maximumBytes else { throw JerdError.corrupt(Self.tooLargeMessage) }
        let journal: RuntimeUpdateJournal
        do {
            journal = try JSONDecoder().decode(RuntimeUpdateJournal.self, from: data)
        } catch {
            throw JerdError.corrupt(Self.invalidJournalMessage)
        }
        guard journal.isValid else { throw JerdError.corrupt(Self.invalidJournalMessage) }
        return journal
    }

    /// Moves an item with `rename`, which never follows a final symbolic link.
    private func move(_ source: URL, to destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else {
            throw JerdError.unavailable(
                "Cannot move \(source.lastPathComponent) aside (\(SystemError.describe(errno))). The files were preserved."
            )
        }
    }
}
