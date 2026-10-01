import Foundation

public struct CLIRuntimeSelection: Sendable {
    public let runtime: DevelopmentRuntime
    public let site: Site?

    /// The most specific registered project owns its nested working directories.
    /// Web enablement does not change a project's explicit PHP selection.
    public static func resolve(configuration: AppConfiguration, workingDirectory: URL) throws -> Self {
        guard configuration.schemaVersion == AppConfiguration.currentVersion else {
            throw JerdError.corruptConfiguration("The Jerd configuration version is unsupported.")
        }
        let current = workingDirectory.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let matches = configuration.sites.compactMap { site -> (Site, Int)? in
            let root = URL(fileURLWithPath: site.projectPath).resolvingSymlinksInPath().standardizedFileURL.pathComponents
            return current.starts(with: root) ? (site, root.count) : nil
        }.sorted { $0.1 > $1.1 }
        if let first = matches.first {
            guard matches.dropFirst().first?.1 != first.1 else {
                throw JerdError.invalid("More than one Jerd site matches this directory.")
            }
            return Self(runtime: try configuration.runtime(for: first.0), site: first.0)
        }
        guard let id = configuration.defaultRuntimeID,
              let runtime = configuration.runtimes.first(where: { $0.id == id }) else {
            throw JerdError.unavailable("Select a default PHP runtime in Jerd.")
        }
        return Self(runtime: runtime, site: nil)
    }
}

public struct CLICompanions: Codable, Sendable {
    public let composerPath: String
    public let laravelPath: String
    public init(composerPath: String, laravelPath: String) {
        self.composerPath = composerPath; self.laravelPath = laravelPath
    }
}
