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
    var logs: URL { path(".build/logs") }

    /// The folder with the pin catalog `runtimes.json` and the Laravel installer project.
    var runtimeSources: URL { path("Runtimes") }
    var runtimeCatalog: URL { path("Runtimes/runtimes.json") }
    /// Prepared payloads in the bundle layout: `<group>/<payload ID>/payload-receipt.json`.
    var payloads: URL { path(".build/runtimes/payloads") }
    /// Verified downloads, one file for each SHA-256.
    var runtimeDownloads: URL { path(".build/runtimes/downloads") }
    /// Support libraries that payloads need, for example the XZ library of RustFS.
    var runtimeSupport: URL { path(".build/runtimes/support") }
    /// Folders that the integration tests read, made from the payload receipts.
    var integrationRuntimes: URL { path(".build/runtimes/integration") }
    var releases: URL { path(".build/releases") }
    var evidence: URL { path(".build/evidence") }
    var versionFile: URL { path("Configuration/Version.xcconfig") }
    var baseConfiguration: URL { path("Configuration/Base.xcconfig") }
    var changelog: URL { path("CHANGELOG.md") }
    var appcast: URL { path("appcast.xml") }
    /// The resolved Sparkle package: the framework and the `bin` tools (`sign_update`, `generate_keys`).
    var sparkleArtifacts: URL { path(".build/SourcePackages/artifacts/sparkle/Sparkle") }
    var sparkleTools: URL { path(".build/SourcePackages/artifacts/sparkle/Sparkle/bin") }
    var embedScript: URL { path("Tools/Scripts/embed-app-contents.sh") }

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
