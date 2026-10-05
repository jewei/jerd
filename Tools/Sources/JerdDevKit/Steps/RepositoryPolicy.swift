import Foundation

/// One repository policy: a title and a check that reads the files it needs and returns its findings.
struct RepositoryPolicy: Sendable {
    var title: String
    var findings: @Sendable (Repository) throws -> [PolicyFinding]

    /// Every policy that `./dev lint` checks, in report order.
    static let all: [RepositoryPolicy] = [
        RepositoryPolicy(title: "Sparkle keys in Info.plist") { repository in
            try SparkleInfoPlistPolicy.findings(plistData: read(SparkleInfoPlistPolicy.file, in: repository))
        },
        RepositoryPolicy(title: "Sparkle version pin") { repository in
            try SparklePinPolicy.findings(
                projectSpec: readText(SparklePinPolicy.specFile, in: repository),
                packageResolved: read(SparklePinPolicy.resolvedFile, in: repository))
        },
        RepositoryPolicy(title: "App update feed URL and public key") { repository in
            let xcconfigs = try FileTree.relativeFilePaths(
                under: repository.path("Configuration"), pathExtension: "xcconfig"
            )
            .map { file in
                let path = "Configuration/\(file)"
                return (path: path, text: try readText(path, in: repository))
            }
            return UpdateSettingsPolicy.findings(
                xcconfigs: xcconfigs, projectSpec: try readText(UpdateSettingsPolicy.projectSpec, in: repository))
        },
        RepositoryPolicy(title: "appcast.xml") { repository in
            try AppcastPolicy.findings(feed: read(AppcastPolicy.file, in: repository))
        },
        RepositoryPolicy(title: "Source file length") { repository in
            try SourceLengthPolicy.findings(files: swiftSources(in: repository))
        },
        RepositoryPolicy(title: "Markdown links") { repository in
            try markdownFiles(in: repository).flatMap { path in
                try MarkdownLinkPolicy.findings(file: path, markdown: readText(path, in: repository)) {
                    FileManager.default.fileExists(atPath: repository.path($0).path)
                }
            }
        },
    ]

    static func read(_ relativePath: String, in repository: Repository) throws -> Data {
        do {
            return try Data(contentsOf: repository.path(relativePath))
        } catch {
            throw DevFailure.checkFailed("\(relativePath) is missing or cannot be read.")
        }
    }

    static func readText(_ relativePath: String, in repository: Repository) throws -> String {
        String(decoding: try read(relativePath, in: repository), as: UTF8.self)
    }

    static func swiftSources(in repository: Repository) throws -> [(path: String, text: String)] {
        try SourceLengthPolicy.checkedFolders.flatMap { folder in
            try FileTree.relativeFilePaths(under: repository.path(folder), pathExtension: "swift").map { file in
                let path = "\(folder)/\(file)"
                return (path, try readText(path, in: repository))
            }
        }
    }

    /// Root documents, everything under `Docs`, and the Tools guide. Symbolic links such as `CLAUDE.md`
    /// are skipped because their target is checked already.
    static func markdownFiles(in repository: Repository) throws -> [String] {
        let rootFiles = try FileManager.default.contentsOfDirectory(atPath: repository.root.path)
            .filter { $0.hasSuffix(".md") && !FileTree.isSymbolicLink(repository.path($0)) }
        let docs = try FileTree.relativeFilePaths(under: repository.path("Docs"), pathExtension: "md")
        let tools = try FileTree.relativeFilePaths(under: repository.path("Tools"), pathExtension: "md")
        return rootFiles.sorted() + docs.map { "Docs/\($0)" } + tools.map { "Tools/\($0)" }
    }
}
