import Foundation
import JerdFoundation

/// Every path of one engine run: the environment folder, the private socket folder, and the CA.
///
/// The product run uses `environment/` with the installation CA. A preflight run uses a
/// throwaway `environment/preflight-<UUID>/` tree with the isolated CA, so it never touches
/// the active run.
public struct RunLayout: Equatable, Hashable, Sendable {
    /// A Unix socket path must be shorter than `sockaddr_un.sun_path` (104 bytes).
    public static let socketPathLimit = 104

    public let environment: EnvironmentLayout
    /// A new private folder for each run. The engine creates it and removes only a folder it created.
    public let socketDirectory: URL
    public let authority: LocalAuthority

    public init(environment: EnvironmentLayout, socketDirectory: URL, authority: LocalAuthority) {
        self.environment = environment
        self.socketDirectory = socketDirectory
        self.authority = authority
    }

    /// The product run: `environment/` and a new `$TMPDIR/jerd-<12 characters>` socket folder.
    public static func product(
        environment: EnvironmentLayout, installationID: UUID,
        temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) -> RunLayout {
        RunLayout(
            environment: environment, socketDirectory: socketFolder(in: temporaryRoot, prefix: "jerd-", length: 12),
            authority: .installation(installationID))
    }

    /// A preflight run below `environment/preflight-<UUID>/`. Its socket folder is never created.
    public static func preflight(
        within environment: EnvironmentLayout, temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) -> RunLayout {
        let tree = DataLayout(root: environment.preflightDirectory(UUID())).environment
        return RunLayout(
            environment: tree, socketDirectory: socketFolder(in: temporaryRoot, prefix: "jerd-pf-", length: 10),
            authority: .isolatedTest)
    }

    /// The root of a preflight tree, which the caller deletes after use.
    public var preflightTree: URL { environment.root.deletingLastPathComponent() }

    /// The root certificate of this run's CA.
    public var rootCertificateFile: URL { authority.rootCertificate(in: environment.certificatesDirectory) }

    /// The process environment of Caddy, PHP-FPM, and their validation commands.
    public var processEnvironment: [String: String] {
        [
            "PHP_INI_SCAN_DIR": environment.emptyINIDirectory.path,
            "XDG_DATA_HOME": environment.certificatesDirectory.path,
            "XDG_CONFIG_HOME": environment.configurationDirectory.path,
        ]
    }

    /// The files of the pool at `index` (its position among the plan's distinct runtimes).
    public func pool(runtimeID: UUID, index: Int) -> PoolLayout {
        PoolLayout(
            runtimeID: runtimeID, directory: environment.phpRuntimeDirectory(runtimeID),
            socket: socketDirectory.appendingPathComponent("php-\(index).sock"))
    }

    private static func socketFolder(in root: URL, prefix: String, length: Int) -> URL {
        root.appendingPathComponent("\(prefix)\(UUID().uuidString.prefix(length))", isDirectory: true)
    }
}
