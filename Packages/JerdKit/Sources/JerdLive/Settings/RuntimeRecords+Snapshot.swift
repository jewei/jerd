import Foundation
import JerdRuntimes
import JerdUI

extension RuntimeRecords {
    /// The Runtimes page snapshot: the versions in use, the managed builds in use, and the
    /// managed build of each registered PHP runtime.
    package func snapshot(managed: [ManagedRuntime]) -> RuntimeInventorySnapshot {
        RuntimeInventorySnapshot(
            versions: versions, phpBuildDigests: phpBuildDigests(managed),
            builds: managed.filter(isInUse).map(Self.installedBuild))
    }

    /// The registered PHP runtime ID → the archive digest of the managed build that supplies it.
    package func phpBuildDigests(_ managed: [ManagedRuntime]) -> [UUID: String] {
        let builds = managed.filter { $0.kind == .php }
        var digests: [UUID: String] = [:]
        for runtime in sites.runtimes {
            if let build = builds.first(where: { Self.same(runtime.cliPath, $0.executable) }) {
                digests[runtime.id] = build.archiveSHA256
            }
        }
        return digests
    }

    /// The tools that a preparation may need: the default PHP CLI runs Composer and the
    /// Laravel installer, and Composer resolves the Laravel installer. `lzma` is the reviewed
    /// XZ library for RustFS.
    package func preparationTools(lzma: SupportLibrary?) -> PreparationTools {
        let php = sites.runtimes.first { $0.id == sites.defaultRuntimeID }
        return PreparationTools(
            phpCLI: php.map { URL(fileURLWithPath: $0.cliPath) },
            composer: companions.map { URL(fileURLWithPath: $0.composerPath) }, lzma: lzma)
    }

    package static func installedBuild(_ build: ManagedRuntime) -> InstalledBuild {
        InstalledBuild(
            kind: build.kind, version: build.version, releaseVersion: build.releaseVersion,
            archiveSHA256: build.archiveSHA256)
    }
}
