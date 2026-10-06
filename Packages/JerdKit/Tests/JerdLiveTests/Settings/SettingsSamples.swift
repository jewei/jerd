import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import JerdWeb

/// Sample records for the Settings adapter tests. Paths are fixed absolute paths that do not
/// exist, so nothing reads or runs them.
enum SettingsSamples {
    static let root = URL(fileURLWithPath: "/nonexistent-jerd-tests/runtime-updates", isDirectory: true)

    static func build(
        _ kind: RuntimeKind, version: String = "1.2.3", digest: String = "abc", executable: String? = nil,
        secondary: String? = nil
    ) -> ManagedRuntime {
        let name = executable ?? kind.rawValue
        let receipt = BuildReceipt(
            kind: kind, version: version, releaseVersion: version, archiveSHA256: digest,
            executable: RelativePath(name)!, secondaryExecutable: secondary.flatMap { RelativePath($0) }, files: [:])
        return ManagedRuntime(
            receipt: receipt,
            directory: root.appendingPathComponent("\(kind.rawValue)-\(version)-arm64-\(digest)", isDirectory: true))
    }

    static func php(_ cliPath: String, version: String = "8.4.1", id: UUID = UUID()) -> DevelopmentRuntime {
        DevelopmentRuntime(
            id: id, cliPath: cliPath, fpmPath: cliPath + "-fpm", version: version, architectures: [.current],
            cliExtensions: [], fpmExtensions: [], inspectedAt: Date(timeIntervalSince1970: 0))
    }

    static func caddy(
        _ path: String = "/nonexistent-jerd-tests/caddy", version: String = "v2.11.4 h1:x="
    ) -> CaddyRuntime {
        CaddyRuntime(path: path, version: version, architectures: [.current])
    }
}
