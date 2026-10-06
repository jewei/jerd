import Foundation
import JerdDatabases
import JerdMail
import JerdManifest
import JerdRuntimes
import JerdStorage
import JerdTunnels
import JerdWeb

/// Every runtime record that an owner saves now: the site configuration, the database,
/// mail, storage, and tunnel runtimes, and the CLI tools record. The Runtimes page derives
/// the versions in use and the managed builds in use from it (spec D U5 and U6).
package struct RuntimeRecords: Equatable, Sendable {
    package var sites: AppConfiguration
    package var databases: [DatabaseRuntime]
    package var mail: MailRuntime?
    package var storage: StorageRuntime?
    package var tunnel: TunnelRuntime?
    package var companions: CLICompanions?

    package init(
        sites: AppConfiguration = AppConfiguration(), databases: [DatabaseRuntime] = [], mail: MailRuntime? = nil,
        storage: StorageRuntime? = nil, tunnel: TunnelRuntime? = nil, companions: CLICompanions? = nil
    ) {
        self.sites = sites
        self.databases = databases
        self.mail = mail
        self.storage = storage
        self.tunnel = tunnel
        self.companions = companions
    }

    /// The versions in use for each kind (U5). Caddy reports `v2.x.y …`; only `2.x.y` counts.
    package var versions: [RuntimeKind: [String]] {
        var versions: [RuntimeKind: [String]] = [
            .php: sites.runtimes.map(\.version),
            .caddy: sites.caddy.map { [Self.caddyVersion($0.version)] } ?? [],
            .composer: companions?.composerVersion.map { [$0] } ?? [],
            .laravel: companions?.laravelVersion.map { [$0] } ?? [],
            .mailpit: mail.map { [$0.version] } ?? [],
            .rustfs: storage.map { [$0.version] } ?? [],
            .cloudflared: tunnel.map { [$0.version] } ?? [],
        ]
        for engine in DatabaseEngine.allCases {
            versions[Self.kind(of: engine)] = databases.filter { $0.engine == engine }.map(\.version)
        }
        return versions
    }

    /// True when a saved record points at the build (U6): its executable for PHP, Caddy,
    /// Composer, and the Laravel installer; its folder for databases, mail, storage, and tunnels.
    package func isInUse(_ build: ManagedRuntime) -> Bool {
        switch build.kind {
        case .php: sites.runtimes.contains { Self.same($0.cliPath, build.executable) }
        case .caddy: sites.caddy.map { Self.same($0.path, build.executable) } ?? false
        case .composer: companions.map { Self.same($0.composerPath, build.executable) } ?? false
        case .laravel: companions.map { Self.same($0.laravelPath, build.executable) } ?? false
        case .mysql, .postgresql, .redis:
            databases.contains { Self.kind(of: $0.engine) == build.kind && Self.same($0.path, build.directory) }
        case .mailpit: mail.map { Self.same($0.path, build.directory) } ?? false
        case .rustfs: storage.map { Self.same($0.path, build.directory) } ?? false
        case .cloudflared: tunnel.map { Self.same($0.path, build.directory) } ?? false
        }
    }

    /// `v2.11.4 h1:…` → `2.11.4`.
    package static func caddyVersion(_ reported: String) -> String {
        let first = reported.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? reported
        return first.hasPrefix("v") ? String(first.dropFirst()) : first
    }

    package static func kind(of engine: DatabaseEngine) -> RuntimeKind {
        switch engine {
        case .mysql: .mysql
        case .postgresql: .postgresql
        case .redis: .redis
        }
    }

    /// True when a saved path names the file or folder. The PHP and Caddy inspectors save
    /// resolved paths, so both sides are compared without links.
    package static func same(_ path: String, _ url: URL) -> Bool {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            == url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
