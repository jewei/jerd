import Foundation

/// The repository root and every path that the tool uses. All paths come from the root, so the
/// tool works the same from any working directory.
struct Repository: Equatable, Sendable {
    let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func path(_ relative: String) -> URL {
        root.appending(path: relative, directoryHint: .inferFromPath)
    }

    var kitPackage: URL { path("Packages/JerdKit") }
    var kitTests: URL { path("Packages/JerdKit/Tests") }
    var toolsPackage: URL { path("Tools") }
    var projectSpec: URL { path("project.yml") }
    var project: URL { path("Jerd.xcodeproj") }
    var formatConfiguration: URL { path(".swift-format") }
    var xcodeVersionFile: URL { path(".xcode-version") }
    var xcodeGenVersionFile: URL { path("Tools/xcodegen-version") }
    var derivedData: URL { path(".build/xcode") }
    var sourcePackages: URL { path(".build/SourcePackages") }
    var snapshots: URL { path(".build/snapshots") }
    var runtimes: URL { path(".build/runtimes") }

    /// The path relative to the root, for messages. Paths outside the root stay absolute.
    func relativePath(of url: URL) -> String {
        let rootPath = root.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
    }

    /// Finds the repository that contains `directory`: the nearest folder with `project.yml` and
    /// `Tools/Package.swift`.
    static func locate(from directory: URL, fileExists: (String) -> Bool) -> Repository? {
        var candidate = directory.standardizedFileURL
        while true {
            let markers = ["project.yml", "Tools/Package.swift"].map { candidate.appending(path: $0).path }
            if markers.allSatisfy(fileExists) {
                return Repository(root: candidate)
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { return nil }
            candidate = parent
        }
    }
}
