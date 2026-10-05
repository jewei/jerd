import Darwin
import Foundation
import JerdFoundation

/// Copies a folder tree, for example from a mounted disk image, without leaving an allowed root (spec D I11).
///
/// Each node is resolved through its links. The resolved path must stay under the resolved `root`.
/// Links are materialized: the copy holds regular files and folders only. Folder link cycles and
/// trees with too many nodes are refused. The work is synchronous; run it off the cooperative pool.
public enum ContainedTreeCopier {
    /// The most nodes (folders and files, selected or not) that one copy visits.
    public static let nodeLimit = 100_000
    /// The largest file that a copy accepts.
    public static let fileSizeLimit: Int64 = 512_000_000

    /// Copies `source` to `destination`. Every resolved node must stay under resolved `root`.
    /// `selects` receives the path relative to `source` and decides which files to copy.
    /// A selected file must be a regular file of at most 512,000,000 bytes.
    public static func copy(
        from source: URL, to destination: URL, root: URL, selects: (RelativePath) -> Bool
    ) throws {
        try copy(from: source, to: destination, root: root, nodeLimit: nodeLimit, selects: selects)
    }

    /// `copy(from:to:root:selects:)` with a node limit that tests can make small.
    package static func copy(
        from source: URL, to destination: URL, root: URL, nodeLimit: Int, selects: (RelativePath) -> Bool
    ) throws {
        var walk = Walk(root: resolved(root).pathComponents, destinationRoot: destination, nodeLimit: nodeLimit)
        let name = RelativePath(source.lastPathComponent)
        try walk.visit(source, to: destination, relative: nil, sourceName: name, selects: selects)
    }

    static func resolved(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    /// The state of one copy: the node count and the stack of resolved folders for cycle detection.
    private struct Walk {
        let root: [String]
        let destinationRoot: URL
        let nodeLimit: Int
        var count = 0
        var folders: [String] = []

        mutating func visit(
            _ source: URL, to target: URL, relative: RelativePath?, sourceName: RelativePath?,
            selects: (RelativePath) -> Bool
        ) throws {
            try Task.checkCancellation()
            let resolved = ContainedTreeCopier.resolved(source)
            guard resolved.pathComponents.starts(with: root) else { throw ArchiveFailure.treeLinkLeavesRoot }
            count += 1
            guard count <= nodeLimit else { throw ArchiveFailure.treeTooManyFiles }
            var info = stat()
            guard lstat(resolved.path, &info) == 0 else { throw ArchiveFailure.treeUnreadable }
            if info.st_mode & S_IFMT == S_IFDIR {
                try visitFolder(resolved, to: target, relative: relative, selects: selects)
            } else if let path = relative ?? sourceName, selects(path) {
                guard info.st_mode & S_IFMT == S_IFREG, info.st_size <= ContainedTreeCopier.fileSizeLimit else {
                    throw ArchiveFailure.treeInvalidFile
                }
                let mode: mode_t = info.st_mode & 0o111 == 0 ? 0o600 : 0o700
                // A single-file source has no destination folder of its own: its parent holds the copy.
                var within = destinationRoot
                if relative == nil {
                    within = target.deletingLastPathComponent()
                    try OwnedDirectory.create(within)
                }
                let output = try OutputFile(target, mode: mode, within: within)
                _ = try output.copyContents(of: resolved, failure: ArchiveFailure.treeInvalidFile)
            }
        }

        private mutating func visitFolder(
            _ folder: URL, to target: URL, relative: RelativePath?, selects: (RelativePath) -> Bool
        ) throws {
            guard !folders.contains(folder.path) else { throw ArchiveFailure.treeCycle }
            folders.append(folder.path)
            defer { folders.removeLast() }
            if relative == nil {
                try OwnedDirectory.create(target)
            } else {
                try OwnedDirectory.create(target, within: destinationRoot)
            }
            let names: [String]
            do {
                names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            } catch {
                throw ArchiveFailure.treeUnreadable
            }
            for name in names {
                guard let child = RelativePath(name) else { throw ArchiveFailure.treeInvalidFile }
                try visit(
                    folder.appendingPathComponent(name), to: target.appendingPathComponent(name),
                    relative: relative.map { $0.appending(child) } ?? child, sourceName: nil, selects: selects)
            }
        }
    }
}
