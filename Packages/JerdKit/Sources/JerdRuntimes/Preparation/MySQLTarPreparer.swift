import Foundation
import JerdArchive
import JerdFoundation

/// MySQL from Oracle's macOS tarball: the server, three clients, their libraries, and shared data.
package struct MySQLTarPreparer: RuntimePreparing {
    package static let binaries: Set<String> = [
        "bin/mysqld", "bin/mysql", "bin/mysqladmin", "bin/mysqldump", "LICENSE", "README",
    ]

    package init() {}

    /// The selection rule of I8: named files, `share/…`, `bin/*.dylib`, and `lib/…` except static libraries.
    package static func selects(_ path: RelativePath) -> Bool {
        let name = path.string
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
