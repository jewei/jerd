import Foundation
import JerdArchive
import JerdFoundation

/// Redis from its verified source tarball, built with the local Command Line Tools.
///
/// Third-party modules are left out except `modules/vector-sets`. The build has no TLS and uses
/// libc malloc. Git reads no system or user configuration and stops at the staging folder.
package struct RedisSourceBuilder: RuntimePreparing {
    package static let makeTimeout: Duration = .seconds(900)
    package static let licenseFiles = ["COPYING", "LICENSE.txt", "REDISCONTRIBUTIONS.txt"]
    package static let objectExtensions: Set<String> = ["o", "a", "so", "dylib"]
    /// The message when this Mac has no compiler: the step that fixes it.
    package static let missingCompiler = JerdError.unavailable(
        "Redis is built from its source on this Mac, and the build needs the Xcode Command Line Tools. Install them with xcode-select --install, then try again."
    )

    package init() {}

    /// The source files to extract (after the root folder is removed).
    package static func selectsSource(_ path: RelativePath) -> Bool {
        path.components.first != "modules" || path.components.dropFirst().first == "vector-sets"
    }

    /// The `make` arguments for `processors` active processors.
    package static func makeArguments(processors: Int) -> [String] {
        ["-j\(max(1, min(4, processors)))", "MALLOC=libc", "BUILD_TLS=no", "redis-server", "redis-cli"]
    }

    package func prepare(_ context: PreparationContext) async throws {
        let source = context.staging.appendingPathComponent("redis-source", isDirectory: true)
        try await RuntimePreparers.extract(
            try context.requireArtifact(), to: source,
            policy: ExtractionPolicy(stripsRoot: true, selects: Self.selectsSource))
        do {
            try await context.run("/usr/bin/xcrun", ["--find", "clang"], in: context.staging)
        } catch let error as JerdError where error.kind == .processFailed {
            throw Self.missingCompiler
        }
        try await context.run(
            "/usr/bin/make", Self.makeArguments(processors: ProcessInfo.processInfo.activeProcessorCount),
            in: source.appendingPathComponent("src"),
            environment: [
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_CEILING_DIRECTORIES": context.staging.path,
            ],
            timeout: Self.makeTimeout)
        let payload = context.payload
        try await BlockingWork.run { try Self.collect(from: source, into: payload) }
    }

    private static func collect(from source: URL, into payload: URL) throws {
        try OwnedDirectory.create(payload.appendingPathComponent("bin"))
        for name in ["redis-server", "redis-cli"] {
            try FileManager.default.copyItem(
                at: source.appendingPathComponent("src/\(name)"), to: payload.appendingPathComponent("bin/\(name)"))
        }
        for name in licenseFiles where FileProbe.presence(at: source.appendingPathComponent(name)) == .present {
            try FileManager.default.copyItem(
                at: source.appendingPathComponent(name), to: payload.appendingPathComponent(name))
        }
        try ContainedTreeCopier.copy(
            from: source.appendingPathComponent("deps"),
            to: payload.appendingPathComponent("build-dependency-notices"), root: source
        ) { !objectExtensions.contains($0.url(in: source).pathExtension) }
    }
}
