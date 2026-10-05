import Foundation

/// The live `MarkdownLinkTargets`: it reads the repository and compares each path component with the
/// real directory entries, so a link with the wrong letter case fails here as it fails on GitHub.
struct RepositoryFiles: MarkdownLinkTargets {
    let repository: Repository

    func exists(_ path: String) -> Bool {
        var folder = repository.root
        for component in path.split(separator: "/") where component != "." {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            guard entries.contains(String(component)) else { return false }
            folder = folder.appending(path: String(component))
        }
        return true
    }

    func markdown(at path: String) -> String? {
        (try? Data(contentsOf: repository.path(path))).map { String(decoding: $0, as: UTF8.self) }
    }
}
