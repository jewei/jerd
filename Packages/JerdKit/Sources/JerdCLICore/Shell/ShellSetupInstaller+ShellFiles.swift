import Darwin
import Foundation
import JerdFoundation

extension ShellSetupInstaller {
    /// Plans every startup file. Reads only; refuses links, foreign files, and malformed blocks.
    func planShellFiles() throws -> [ShellFileChange] {
        var current: [(URL, Data, mode_t)] = []
        for name in Self.shellFileNames {
            let file = home.appendingPathComponent(name)
            if let (data, mode) = try readShellFile(file) { current.append((file, data, mode)) }
        }
        let changes =
            current.isEmpty
            ? [
                try ShellFileChange(
                    file: home.appendingPathComponent(Self.newShellFileName), original: nil,
                    mode: ShellFileChange.newFileMode)
            ]
            : try current.map { try ShellFileChange(file: $0.0, original: $0.1, mode: $0.2) }
        for change in changes where change.changesFile { try StagedFile.checkLeftover(change.stage) }
        return changes
    }

    /// The bytes and mode of a startup file, or nil when it does not exist.
    func readShellFile(_ file: URL) throws -> (Data, mode_t)? {
        var info = stat()
        guard lstat(file.path, &info) == 0 else {
            let code = errno
            guard code == ENOENT else {
                throw JerdError.unavailable("Cannot inspect \(file.path) (\(SystemError.describe(code))).")
            }
            return nil
        }
        let manual = "It was preserved. Add the Jerd PATH block yourself."
        switch info.st_mode & S_IFMT {
        case S_IFLNK: throw JerdError.invalid("\(file.path) is a symbolic link. \(manual)")
        case S_IFREG: break
        default: throw JerdError.invalid("\(file.path) is not a regular file. \(manual)")
        }
        guard info.st_uid == geteuid(), info.st_nlink == 1 else {
            throw JerdError.invalid("\(file.path) belongs to another user or has more than one link. \(manual)")
        }
        return (try AtomicFile.read(file, limit: Self.shellFileLimit), info.st_mode & 0o7777)
    }

    /// Saves the original bytes of the changed files that exist. Nil when there are none.
    func backUp(_ changes: [ShellFileChange]) throws -> URL? {
        let originals = changes.compactMap { change in change.original.map { (change.file.lastPathComponent, $0) } }
        guard !originals.isEmpty else { return nil }
        try OwnedDirectory.create(layout.shellBackupsDirectory, within: layout.root)
        let folder = layout.shellBackupsDirectory.appendingPathComponent(
            ShellBackupName.folderName(for: now(), timeZone: timeZone), isDirectory: true)
        guard mkdir(folder.path, OwnedDirectory.mode) == 0 else {
            let code = errno
            throw JerdError.unavailable(
                "Cannot create the shell backup folder \(folder.path) (\(SystemError.describe(code))). Try again.")
        }
        for (name, data) in originals { try AtomicFile.write(data, to: folder.appendingPathComponent(name)) }
        return folder
    }

    /// Replaces each file. After a failure, the files that were already replaced get their original
    /// bytes back, so the setup changes all files or none.
    func replace(_ changes: [ShellFileChange], backup: URL?) throws {
        var replaced: [ShellFileChange] = []
        do {
            for change in changes {
                try StagedFile.removeLeftover(change.stage)
                try StagedFile.write(change.updated, to: change.stage, mode: change.mode)
                guard try readShellFile(change.file)?.0 == change.original else {
                    try StagedFile.removeLeftover(change.stage)
                    throw JerdError.unavailable(
                        "\(change.file.path) changed during the setup. Set up the commands again.")
                }
                try StagedFile.commit(change.stage, to: change.file)
                replaced.append(change)
            }
        } catch {
            try restore(replaced.reversed(), after: error, backup: backup)
            throw error
        }
    }

    private func restore(_ changes: [ShellFileChange], after failure: any Error, backup: URL?) throws {
        for change in changes {
            do {
                if let original = change.original {
                    try StagedFile.removeLeftover(change.stage)
                    try StagedFile.write(original, to: change.stage, mode: change.mode)
                    try StagedFile.commit(change.stage, to: change.file)
                } else {
                    try AtomicFile.remove(change.file)
                }
            } catch {
                let source = backup.map { " Restore it from \($0.path)." } ?? ""
                throw JerdError.partialChange(
                    "The shell setup failed: \(FailureDetail.describe(failure)) \(change.file.path) kept the "
                        + "Jerd PATH block because the restore failed: \(FailureDetail.describe(error))\(source)")
            }
        }
    }
}
