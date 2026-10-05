import Foundation

/// Small synchronous file operations for the steps. The tool runs them from its command task, never
/// from a UI thread.
enum FileTree {
    /// Regular files under `folder`, keyed by their path relative to `folder`.
    static func readFiles(under folder: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for path in try relativeFilePaths(under: folder) {
            files[path] = try Data(contentsOf: folder.appending(path: path))
        }
        return files
    }

    /// Build output folders. They are never sources, and they can hold many thousands of files.
    static let skippedFolderNames: Set<String> = [".build", ".swiftpm", ".git"]

    /// Relative paths of the regular files under `folder`, sorted. Symbolic links are not followed.
    static func relativeFilePaths(under folder: URL, pathExtension: String? = nil) throws -> [String] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.path) else { return [] }
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else {
            throw DevFailure.checkFailed("Could not read the folder \(folder.path).")
        }
        var paths: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true, skippedFolderNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            guard pathExtension.map({ url.pathExtension == $0 }) ?? true else { continue }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            if path.hasPrefix(base) {
                paths.append(String(path.dropFirst(base.count)))
            }
        }
        return paths.sorted()
    }

    /// Copies files, given relative to `source`, to the same relative paths under `destination`.
    /// Files that Git lists but that are deleted in the working tree are skipped.
    static func copy(_ relativePaths: [String], from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        for path in relativePaths {
            let from = source.appending(path: path)
            guard (try? from.checkResourceIsReachable()) == true || isSymbolicLink(from) else { continue }
            let to = destination.appending(path: path)
            try manager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: from, to: to)
        }
    }

    /// Names of the direct subfolders of `folder`, sorted.
    static func subfolderNames(of folder: URL) throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return try contents.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
            .map(\.lastPathComponent).sorted()
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// A new empty folder in the temporary folder of the user.
    static func makeTemporaryFolder(prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
