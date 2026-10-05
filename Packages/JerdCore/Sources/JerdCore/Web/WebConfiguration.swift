import Foundation
import Darwin

public struct WebConfiguration: Sendable {
    public let sites: [SiteRuntime]
    public let caddy: CaddyRuntime
    public init(sites: [SiteRuntime], caddy: CaddyRuntime) { self.sites = sites; self.caddy = caddy }
    public init(_ configuration: AppConfiguration, siteIDs: Set<UUID>? = nil) throws {
        guard let caddy = configuration.caddy else { throw JerdError.unavailable("Caddy is unavailable.") }
        self.caddy = caddy
        sites = try configuration.sites.filter { $0.isEnabled && (siteIDs?.contains($0.id) ?? true) }
            .map { SiteRuntime(site: $0, runtime: try configuration.runtime(for: $0)) }
    }

    func servesTheSameConfiguration(as other: Self) -> Bool {
        guard caddy == other.caddy, sites.count == other.sites.count else { return false }
        return sites.allSatisfy { entry in
            guard let previous = other.sites.first(where: { $0.site.id == entry.site.id }) else { return false }
            let site = entry.site, old = previous.site, runtime = entry.runtime, oldRuntime = previous.runtime
            return site.hostname == old.hostname && site.projectPath == old.projectPath && site.documentRoot == old.documentRoot &&
                runtime.id == oldRuntime.id && runtime.cliPath == oldRuntime.cliPath && runtime.fpmPath == oldRuntime.fpmPath &&
                runtime.version == oldRuntime.version && runtime.architectures == oldRuntime.architectures &&
                runtime.cliExtensions == oldRuntime.cliExtensions && runtime.fpmExtensions == oldRuntime.fpmExtensions
        }
    }

    func executableStamps() throws -> [String: ExecutableStamp] {
        let paths = Set([caddy.path] + sites.flatMap { [$0.runtime.cliPath, $0.runtime.fpmPath] })
        return try Dictionary(uniqueKeysWithValues: paths.map { ($0, try ExecutableStamp(path: $0)) })
    }
}

/// A one-use preflight result from a specific environment operation.
public struct PreparedWebConfiguration: Sendable {
    let id: UUID
    let environmentID: UUID
    let configuration: WebConfiguration
    let stamps: [String: ExecutableStamp]
}

struct ExecutableStamp: Equatable, Sendable {
    private let device: Int32
    private let inode: UInt64
    private let size: Int64
    private let modifiedSeconds: Int
    private let modifiedNanoseconds: Int
    private let changedSeconds: Int
    private let changedNanoseconds: Int
    init(path: String) throws {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, access(path, X_OK) == 0 else {
            throw JerdError.unavailable("A selected runtime executable is unavailable: \(path)")
        }
        device = info.st_dev; inode = info.st_ino; size = info.st_size
        modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanoseconds = info.st_mtimespec.tv_nsec
        changedSeconds = info.st_ctimespec.tv_sec; changedNanoseconds = info.st_ctimespec.tv_nsec
    }
}
