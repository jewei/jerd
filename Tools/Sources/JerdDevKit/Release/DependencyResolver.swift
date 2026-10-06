import Foundation

/// Resolves the library references of a payload binary without the libraries of the build Mac.
///
/// A signed payload must be self-contained: each reference is a macOS system library or a regular
/// file inside the payload folder. An absolute path elsewhere (for example Homebrew) is refused.
struct DependencyResolver: Sendable {
    /// The payload folder.
    let payload: URL
    /// True for a regular file that is not a symbolic link.
    let isRegularFile: @Sendable (URL) -> Bool

    init(payload: URL, isRegularFile: @escaping @Sendable (URL) -> Bool = Self.regularFile) {
        self.payload = payload.standardizedFileURL
        self.isRegularFile = isRegularFile
    }

    /// The bundled file of `dependency`, or nil for a system library.
    /// - Throws: `DevFailure.checkFailed` when the reference leaves the payload or names no file.
    func resolve(_ dependency: String, of binary: URL, rpaths: [String]) throws -> URL? {
        if dependency.hasPrefix("/usr/lib/") || dependency.hasPrefix("/System/Library/") { return nil }
        let candidates: [URL]
        if let suffix = dependency.dropPrefix("@rpath/") {
            candidates =
                rpaths.compactMap { expand($0, binary: binary)?.appending(path: suffix) }
                + [payload.appending(path: "lib/\(suffix)"), executableFolder.appending(path: suffix)]
        } else {
            candidates = expand(dependency, binary: binary).map { [$0] } ?? []
        }
        for candidate in candidates.map(\.standardizedFileURL) where isInside(candidate) && isRegularFile(candidate) {
            return candidate
        }
        let name = binary.lastPathComponent
        throw DevFailure.checkFailed("\(name) needs \(dependency), which the payload does not contain.")
    }

    /// `@executable_path` of a payload: its `bin` folder when it has one, else the payload folder.
    var executableFolder: URL {
        let bin = payload.appending(path: "bin")
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: bin.path, isDirectory: &isFolder) && isFolder.boolValue
            ? bin : payload
    }

    private func expand(_ path: String, binary: URL) -> URL? {
        if let rest = path.dropPrefix("@loader_path/") {
            return binary.deletingLastPathComponent().appending(path: rest)
        }
        if let rest = path.dropPrefix("@executable_path/") { return executableFolder.appending(path: rest) }
        return path.hasPrefix("/") ? URL(filePath: path) : nil
    }

    private func isInside(_ url: URL) -> Bool { url.path.hasPrefix(payload.path + "/") }

    @Sendable static func regularFile(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
    }
}

extension String {
    /// The rest of the string after `prefix`, or nil when it does not start with it.
    fileprivate func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
