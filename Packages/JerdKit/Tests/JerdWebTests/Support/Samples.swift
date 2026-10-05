import Foundation

@testable import JerdWeb

/// Small value builders shared by the tests.
enum Samples {
    static let runtimeID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

    static func site(
        _ root: URL, hostname: String = "demo.test", id: UUID = UUID(), documentRoot: URL? = nil,
        selection: PHPSelection = .followDefault, enabled: Bool = true
    ) -> Site {
        Site(
            id: id, displayName: "Demo", projectPath: root.path, documentRoot: (documentRoot ?? root).path,
            hostname: hostname, phpSelection: selection, isEnabled: enabled)
    }

    static func runtime(
        id: UUID = UUID(), cli: String = "/local/php", fpm: String = "/local/php-fpm", version: String = "8.4.0",
        extensions: [String] = ["Core", "json"]
    ) -> DevelopmentRuntime {
        DevelopmentRuntime(
            id: id, cliPath: cli, fpmPath: fpm, version: version, architectures: [.current],
            cliExtensions: extensions, fpmExtensions: extensions, inspectedAt: Date(timeIntervalSinceReferenceDate: 1))
    }

    static func caddy(path: String = "/local/caddy", version: String = "v2.11.4") -> CaddyRuntime {
        CaddyRuntime(path: path, version: version, architectures: [.current])
    }

    /// A configuration with one runtime as the default, Caddy, and `sites`.
    static func configuration(_ sites: [Site], runtime: DevelopmentRuntime = runtime(id: runtimeID)) -> AppConfiguration
    {
        AppConfiguration(sites: sites, runtimes: [runtime], defaultRuntimeID: runtime.id, caddy: caddy())
    }
}
