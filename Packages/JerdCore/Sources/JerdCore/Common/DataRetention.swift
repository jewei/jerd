import Foundation
import Darwin

enum DataSize {
    static func bytes(in root: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else {
            throw JerdError.unavailable("Cannot inspect the retained data folder.")
        }
        var size: Int64 = 0, count = 0
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            count += 1
            guard count <= 1_000_000 else { throw JerdError.unavailable("This data folder is too large for a size check. Its files were preserved.") }
            let values = try file.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true { size += Int64(values.fileSize ?? 0) }
        }
        return size
    }
}

public struct RetainedBackup: Identifiable, Sendable {
    public let id: String
    public let service: String
    public let directory: URL
    public let bytes: Int64?
    public let detail: String
    public let isProtected: Bool
}

/// Explicit cleanup for fixed, app-owned backup locations. A pending or corrupt
/// recovery journal protects every backup for that service.
public actor BackupRetentionStore {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func inspect() throws -> [RetainedBackup] {
        var result: [RetainedBackup] = []
        for service in ["mail", "storage"] {
            let root = directory.appendingPathComponent(service)
            let parent = root.appendingPathComponent("runtime-backups")
            guard FileManager.default.fileExists(atPath: parent.path) else { continue }
            try requireDirectory(root); try requireDirectory(parent)
            let pending = PrivateFiles.exists(root.appendingPathComponent("runtime-update.json"))
            for folder in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
                guard UUID(uuidString: folder.lastPathComponent) != nil else { continue }
                do {
                    try requireDirectory(folder)
                    let size = try DataSize.bytes(in: folder)
                    result.append(.init(id: "\(service)/\(folder.lastPathComponent)", service: service.capitalized, directory: folder,
                        bytes: size, detail: pending ? "Protected while a runtime update needs recovery." : "Saved data and settings from a runtime update. Delete only when you no longer need this copy.", isProtected: pending))
                } catch {
                    result.append(.init(id: "\(service)/\(folder.lastPathComponent)", service: service.capitalized, directory: folder,
                        bytes: nil, detail: error.localizedDescription, isProtected: true))
                }
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    public func remove(_ id: String) throws {
        let parts = id.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, ["mail", "storage"].contains(String(parts[0])), UUID(uuidString: String(parts[1])) != nil else {
            throw JerdError.invalid("The selected backup ID is invalid.")
        }
        let root = directory.appendingPathComponent(String(parts[0]))
        try requireDirectory(root)
        let descriptor = open(root.appendingPathComponent("service.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw JerdError.unavailable("Cannot lock the service backup.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw JerdError.unavailable("Stop this service before deleting a backup.") }
        defer { _ = flock(descriptor, LOCK_UN) }
        guard !PrivateFiles.exists(root.appendingPathComponent("runtime-update.json")) else {
            throw JerdError.unavailable("Complete runtime recovery before deleting service backups.")
        }
        try PreviousProcessRun.requireStopped(at: root.appendingPathComponent("active-run.json"))
        let parent = root.appendingPathComponent("runtime-backups")
        let folder = parent.appendingPathComponent(String(parts[1]))
        try requireDirectory(parent); try requireDirectory(folder)
        // Only remove the selected backup tree. Never touch the current data directory.
        try FileManager.default.removeItem(at: folder)
    }

    private func requireDirectory(_ url: URL) throws {
        try PrivateFiles.requireDirectory(url, within: directory)
    }
}
