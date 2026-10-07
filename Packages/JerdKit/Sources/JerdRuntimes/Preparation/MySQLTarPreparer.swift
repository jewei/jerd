import Foundation
import JerdArchive
import JerdFoundation

/// MySQL from Oracle's macOS tarball: the server, three clients, their libraries, and shared data.
package struct MySQLTarPreparer: RuntimePreparing {
    package static let binaries: Set<String> = [
        "bin/mysqld", "bin/mysql", "bin/mysqladmin", "bin/mysqldump", "LICENSE", "README",
    ]

    package init() {}

    /// Files that the rule leaves out of `lib/`: the debug builds of the plugins, and the WebAuthn
    /// client plugin with its private `libfido2`. Upstream links `lib/plugin/libfido2.1.dylib` to
    /// `lib/`; extracted as a file, its `@loader_path/../lib/libcrypto.3.dylib` cannot resolve. Jerd
    /// never rewrites Oracle-signed files, and neither `mysqld` nor the default
    /// `caching_sha2_password` accounts use the plugin (the server side is Enterprise only).
    package static let leftOut: [String] = [
        "lib/plugin/debug/", "lib/plugin/authentication_webauthn_client.so", "lib/plugin/libfido2.1.dylib",
    ]

    /// The selection rule: named files, `share/…`, `bin/*.dylib`, and `lib/…` except static libraries
    /// and the `leftOut` files.
    package static func selects(_ path: RelativePath) -> Bool {
        let name = path.string
        if leftOut.contains(where: { $0.hasSuffix("/") ? name.hasPrefix($0) : name == $0 }) { return false }
        return binaries.contains(name) || name.hasPrefix("share/")
            || (name.hasPrefix("bin/") && name.hasSuffix(".dylib"))
            || (name.hasPrefix("lib/") && !name.hasSuffix(".a"))
    }

    package func prepare(_ context: PreparationContext) async throws {
        try await RuntimePreparers.extract(
            try context.requireArtifact(), to: context.payload,
            policy: ExtractionPolicy(stripsRoot: true, selects: Self.selects))
        try RuntimePreparers.requireFiles(["bin/mysqld", "bin/mysql"], in: context.payload, kind: .mysql)
    }
}
