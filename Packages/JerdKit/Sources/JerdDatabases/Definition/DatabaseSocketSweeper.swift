import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// Removes the socket folders of earlier runs that ended without a stop, for example after a
/// crash of Jerd (spec E 7.2.4).
///
/// A folder is removed only when every check proves that no process uses it:
/// - it is a real `jerd-db-*` folder with an owner marker of this user;
/// - the marker names an existing instance folder of this data root;
/// - the instance lock is free, and the start gate proves that no saved process lives.
///
/// Every failed check keeps the folder, which is the safe direction. Folders of older builds
/// (without a marker), of another data root, or of a live process stay.
struct DatabaseSocketSweeper: Sendable {
    let temporaryRoot: URL
    let layout: DatabasesLayout
    let startGate: StartGate

    /// - Returns: the removed folders.
    @discardableResult
    func sweep() -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: temporaryRoot.path) else { return [] }
        var removed: [URL] = []
        for name in names.sorted() where name.hasPrefix(DatabaseSocketFolder.prefix) {
            let folder = temporaryRoot.appendingPathComponent(name, isDirectory: true)
            guard let instance = owner(of: folder), removeIfUnused(folder, of: instance) else { continue }
            removed.append(folder)
        }
        return removed
    }

    /// The instance that the marker of `folder` names, when it belongs to this data root.
    private func owner(of folder: URL) -> DatabaseInstanceLayout? {
        let marker = folder.appendingPathComponent(DatabaseSocketFolder.ownerFileName)
        guard DataFolder.isRealDirectory(folder),
            let owner = try? MarkerFile.read(DatabaseSocketFolder.Owner.self, from: marker)
        else { return nil }
        let named = URL(fileURLWithPath: owner.instance, isDirectory: true).standardizedFileURL
        guard let id = UUID(uuidString: named.lastPathComponent), id.uuidString == named.lastPathComponent else {
            return nil
        }
        let instance = layout.instance(id)
        guard instance.root.standardizedFileURL.path == named.path, DataFolder.isRealDirectory(instance.root) else {
            return nil
        }
        return instance
    }

    /// Removes `folder` while this sweep holds the instance lock and the start gate proves that
    /// no saved process lives. A stale run record is removed under the lock, as a start does.
    private func removeIfUnused(_ folder: URL, of instance: DatabaseInstanceLayout) -> Bool {
        guard let lock = try? InstanceLock.acquire(at: instance.lockFile, messages: DatabaseMessages.instance.lock)
        else { return false }
        defer { lock.release() }
        guard (try? startGate.requireStopped(instance.record, holding: lock)) != nil else { return false }
        return (try? FileManager.default.removeItem(at: folder)) != nil
    }
}
