import Foundation
import JerdArchive
import JerdFoundation

/// PostgreSQL 18 from the Postgres.app disk image, after its Developer ID signature check.
///
/// Copies `bin`, `lib`, and `share` of `Contents/Versions/18` (links materialized, never leaving
/// that folder), without static libraries and without the PL/Python extensions, which need a
/// Python framework that Jerd does not supply. Adds the Postgres.app credits.
package struct PostgresAppPreparer: RuntimePreparing {
    package static let app = "Postgres.app"
    package static let versionFolder = "Contents/Versions/18"
    /// The PL/Python modules of PostgreSQL that load an external Python framework.
    package static let pythonModules = ["plpython3", "hstore_plpython3", "jsonb_plpython3", "ltree_plpython3"]

    package init() {}

    /// True for files that the payload keeps.
    /// ICU tool libraries that nothing in the payload loads. They name their ICU dependencies by
    /// bare file name (`libicuuc.77.dylib`), which dyld cannot resolve inside the payload.
    package static let unusedICULibraries = ["libicuio", "libicutest", "libicutu"]

    package static func selects(_ path: RelativePath) -> Bool {
        let name = path.components.last ?? ""
        if name.hasSuffix(".a") { return false }
        if path.components.first == "lib", unusedICULibraries.contains(where: { name.hasPrefix("\($0).") }) {
            return false
        }
        if path.components.first == "lib", pythonModules.contains(where: { name.hasPrefix("\($0).") }) { return false }
        let isExtensionFile = path.components.count >= 2 && path.components.dropLast().last == "extension"
        return !(isExtensionFile && pythonModules.contains { name.hasPrefix("\($0)u.") || name.hasPrefix("\($0)u--") })
    }

    package func prepare(_ context: PreparationContext) async throws {
        let mount = context.staging.appendingPathComponent("volume", isDirectory: true)
        try OwnedDirectory.create(mount)
        let payload = context.payload
        try await DiskImageMount(context: context).withVerifiedApp(
            image: try context.requireArtifact(), mountPoint: mount, app: Self.app, requirement: .postgresApp
        ) { app in
            try await BlockingWork.run { try Self.copy(from: app, to: payload) }
        }
    }

    private static func copy(from app: URL, to payload: URL) throws {
        let root = app.appendingPathComponent(versionFolder)
        for name in ["bin", "lib", "share"] {
            guard let top = RelativePath(name) else { continue }
            try ContainedTreeCopier.copy(
                from: root.appendingPathComponent(name), to: payload.appendingPathComponent(name), root: root
            ) { selects(top.appending($0)) }
        }
        try FileManager.default.copyItem(
            at: app.appendingPathComponent("Contents/Resources/Credits.rtf"),
            to: payload.appendingPathComponent("PostgresApp-Credits.rtf"))
        try RuntimePreparers.requireFiles(["bin/postgres", "bin/psql"], in: payload, kind: .postgresql)
    }
}
