import Foundation

/// A durable undo record for a stopped, locked service. Backups remain after success.
struct ServiceUpdateBackup {
    private struct Journal: Codable { let id: UUID; let names: [String]; let present: Set<String> }
    let root: URL
    let names: [String]
    private var journalURL: URL { root.appendingPathComponent("runtime-update.json") }
    var isPending: Bool { FileManager.default.fileExists(atPath: journalURL.path) }

    func begin() throws -> URL {
        guard !isPending else { throw JerdError.unavailable("Recover the previous runtime update before starting another update.") }
        let parent = root.appendingPathComponent("runtime-backups")
        try PrivateFiles.directory(parent)
        let id = UUID()
        let folder = parent.appendingPathComponent(id.uuidString)
        try PrivateFiles.directory(folder)
        var present = Set<String>()
        for name in names {
            let source = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                try validateTree(source)
                try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
                present.insert(name)
            }
        }
        try PrivateFiles.write(JSONEncoder().encode(Journal(id: id, names: names, present: present)), to: journalURL)
        return folder
    }
    func commit() throws { try FileManager.default.removeItem(at: journalURL) }

    func restoreIfNeeded() throws {
        guard isPending else { return }
        let data = try Data(contentsOf: journalURL)
        guard data.count < 65_536 else { throw JerdError.corruptConfiguration("The runtime update record is too large.") }
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        guard journal.names == names, journal.present.isSubset(of: Set(names)) else {
            throw JerdError.corruptConfiguration("The runtime update record is invalid. Backup files were preserved.")
        }
        let parent = root.appendingPathComponent("runtime-backups")
        let folder = parent.appendingPathComponent(journal.id.uuidString)
        try requireDirectory(parent); try requireDirectory(folder)
        // Validate every backup before moving any current file. Originals are never removed.
        for name in journal.present { try validateTree(folder.appendingPathComponent(name)) }
        let failed = folder.appendingPathComponent("failed-attempt-\(UUID())")
        try PrivateFiles.directory(failed)
        for name in names {
            let target = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.moveItem(at: target, to: failed.appendingPathComponent(name))
            }
            if journal.present.contains(name) {
                try FileManager.default.copyItem(at: folder.appendingPathComponent(name), to: target)
            }
        }
        try commit()
    }

    private func requireDirectory(_ path: URL) throws {
        let info = try path.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw JerdError.invalid("A runtime backup directory is invalid.") }
    }
    private func validateTree(_ path: URL) throws {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        func validate(_ url: URL) throws {
            let info = try url.resourceValues(forKeys: keys)
            guard info.isSymbolicLink != true, info.isDirectory == true || info.isRegularFile == true else {
                throw JerdError.invalid("A service data file is not a regular file or directory. The update was stopped.")
            }
        }
        try validate(path)
        var pending = [path]
        while let item = pending.popLast() {
            try validate(item)
            if try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                pending.append(contentsOf: try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: Array(keys)))
            }
        }
    }
}
