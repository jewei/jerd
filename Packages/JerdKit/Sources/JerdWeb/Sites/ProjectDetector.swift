import Foundation

/// Suggests a document root from file metadata only. It never runs `artisan` or any project code.
public struct ProjectDetector: Sendable {
    /// The files that together identify a Laravel project, relative to the project folder.
    public static let laravelMarkers = ["artisan", "composer.json", "public/index.php"]

    private let files: any ProjectFileInspecting

    public init(files: any ProjectFileInspecting = PathCanonicalizer()) {
        self.files = files
    }

    /// Laravel (all markers are files) suggests `<project>/public`; any other project suggests itself.
    public func suggestDocumentRoot(projectPath: String) throws -> DocumentRootSuggestion {
        let project = URL(fileURLWithPath: try files.canonicalDirectory(projectPath))
        let isLaravel = Self.laravelMarkers.allSatisfy { files.isFile(project.appendingPathComponent($0).path) }
        let root = isLaravel ? project.appendingPathComponent("public") : project
        return DocumentRootSuggestion(path: root.path, isLaravel: isLaravel)
    }
}
