import Foundation
import JerdFoundation
import JerdWeb

/// Selects the PHP runtime of a command from the working directory.
///
/// Rules:
/// - Paths are compared by components after symbolic link resolution: `/a/b` contains `/a/b/c`,
///   but not `/a/bc`.
/// - The registered project with the most components that contains the directory wins. Two
///   projects of equal depth are an error.
/// - Every registered site counts, also a site whose web server is disabled.
/// - A site uses its pin or the default. A missing selection fails; there is no fallback.
/// - Outside every project, the default runtime runs.
///
/// The rule is pure over the injected path resolver. The live resolver uses Foundation's
/// `resolvingSymlinksInPath`, the same form as the saved project paths.
public struct CLIRuntimeResolver: Sendable {
    /// Turns a path into its resolved absolute form.
    public typealias PathResolver = @Sendable (String) -> String

    /// The live resolver, consistent with `PathCanonicalizer` in JerdWeb.
    public static let resolveSymbolicLinks: PathResolver = { path in
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private let resolvePath: PathResolver

    public init(resolvePath: @escaping PathResolver = CLIRuntimeResolver.resolveSymbolicLinks) {
        self.resolvePath = resolvePath
    }

    /// - Throws: `.invalid` for two equally deep matches; `.unavailable` for a missing selection.
    public func resolve(_ configuration: AppConfiguration, workingDirectory: String) throws -> CLIRuntimeSelection {
        let current = components(workingDirectory)
        let matches = configuration.sites.compactMap { site -> (site: Site, depth: Int)? in
            let root = components(site.projectPath)
            return current.starts(with: root) ? (site, root.count) : nil
        }.sorted { $0.depth > $1.depth }
        guard let best = matches.first else { return try defaultSelection(configuration) }
        if matches.count > 1, matches[1].depth == best.depth {
            throw JerdError.invalid("More than one Jerd site matches this directory.")
        }
        do {
            return CLIRuntimeSelection(runtime: try configuration.runtime(for: best.site), site: best.site)
        } catch let error as JerdError where error.kind == .unavailable {
            // The configuration names no site; the CLI message names the site that selected PHP.
            throw JerdError.unavailable(
                "The PHP runtime selected for \(best.site.hostname) is not installed. "
                    + "Select an installed runtime for this site in Jerd.")
        }
    }

    private func defaultSelection(_ configuration: AppConfiguration) throws -> CLIRuntimeSelection {
        guard let id = configuration.defaultRuntimeID,
            let runtime = configuration.runtimes.first(where: { $0.id == id })
        else { throw JerdError.unavailable("Select a default PHP runtime in Jerd.") }
        return CLIRuntimeSelection(runtime: runtime, site: nil)
    }

    private func components(_ path: String) -> [String] {
        URL(fileURLWithPath: resolvePath(path)).standardizedFileURL.pathComponents
    }
}
