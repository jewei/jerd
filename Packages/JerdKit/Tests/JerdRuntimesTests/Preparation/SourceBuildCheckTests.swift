import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess
import JerdRuntimes
import Testing

@Suite struct SourceBuildCheckTests {
    private func write(_ files: [String: Data], in folder: TemporaryFolder) throws -> [RelativePath] {
        try files.map { name, data in
            let url = folder.path(name)
            try OwnedDirectory.create(url.deletingLastPathComponent())
            try data.write(to: url)
            return try #require(RelativePath(name))
        }
    }

    @Test func aFileForANewerMacOSIsNamedWithItsVersion() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let files = try write(
            [
                "bin/redis-cli": MinimumMachO.file(packed: MinimumMachO.twentySeven),
                "bin/redis-server": MinimumMachO.file(packed: MinimumMachO.fourteen),
                "COPYING": Data("license".utf8), "empty": Data(),
            ], in: folder)
        let problems = try SourceBuildCheck.problems(files: files, in: folder.url, minimum: .jerdKitMinimum)
        #expect(problems == ["bin/redis-cli needs macOS 27.0"])
        let message =
            "The Redis build does not run on macOS 14.0, the oldest macOS that Jerd supports: "
            + "bin/redis-cli needs macOS 27.0. Jerd installed nothing."
        #expect(throws: JerdError.invalid(message)) {
            try SourceBuildCheck.verify(.redis, files: files, in: folder.url, minimum: .jerdKitMinimum)
        }
        try SourceBuildCheck.verify(.redis, files: files, in: folder.url, minimum: MinimumMacOS(major: 27, minor: 0))
    }

    @Test func aUniversalFileIsReportedBecauseTheCheckCannotReadIt() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let files = try write(["bin/tool": Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2])], in: folder)
        #expect(
            try SourceBuildCheck.problems(files: files, in: folder.url, minimum: .jerdKitMinimum) == [
                "bin/tool is a universal file, which a source build never makes"
            ])
    }

    @Test func onlyTheRedisPreparerBuildsFromSource() {
        for kind in RuntimeKind.allCases {
            #expect(RuntimePreparers.preparer(for: kind).buildsFromSource == (kind == .redis))
        }
    }

    @Test func redisTargetsTheAppMinimumForTheCompilerAndTheLinker() {
        let environment = RedisSourceBuilder.makeEnvironment(
            staging: URL(fileURLWithPath: "/staging"), minimum: MinimumMacOS(major: 14, minor: 0),
            architecture: .arm64)
        #expect(environment["MACOSX_DEPLOYMENT_TARGET"] == "14.0")
        #expect(environment["CFLAGS"] == "-arch arm64 -mmacosx-version-min=14.0")
        #expect(environment["LDFLAGS"] == "-arch arm64 -mmacosx-version-min=14.0")
        #expect(environment["GIT_CEILING_DIRECTORIES"] == "/staging")
        #expect(environment["GIT_CONFIG_NOSYSTEM"] == "1" && environment["GIT_CONFIG_GLOBAL"] == "/dev/null")
    }
}

/// The whole pipeline with a Redis source build whose `make` writes Mach-O files for `minos`.
@Suite struct RedisSourceBuildPipelineTests {
    private struct Fixture {
        let release: RuntimeRelease
        let fetcher: FakeFetcher
        let commands: ScriptedCommandRunner

        init(builtFor packed: UInt32) throws {
            var tar = TarBuilder()
            tar.file("redis-8.8.3/src/server.c", "int main(void) { return 0; }")
            tar.file("redis-8.8.3/deps/README.md", "dependencies")
            tar.file("redis-8.8.3/COPYING", "license")
            let url = try URL.runtime("https://download.redis.io/releases/redis-8.8.3.tar.gz")
            release = RuntimeRelease(
                kind: .redis, version: "8.8.3", artifact: .archive(url, size: .exact(Int64(tar.data.count))),
                archiveSHA256: FileDigest.hexSHA256(of: tar.data),
                releasePage: try .runtime("https://download.redis.io"),
                architecture: .arm64)
            fetcher = FakeFetcher([url: tar.data])
            commands = ScriptedCommandRunner { request in
                if request.executable.lastPathComponent == "make" {
                    for name in ["redis-server", "redis-cli"] {
                        try MinimumMachO.file(packed: packed).write(
                            to: request.workingDirectory.appendingPathComponent(name))
                    }
                }
                return CommandResult(status: 0, output: "Redis server v=8.8.3 sha=00000000:0 malloc=libc bits=64")
            }
        }

        func installer(_ folder: TemporaryFolder) -> RuntimeInstaller {
            RuntimeInstaller(
                directory: folder.url, fetcher: fetcher, commands: commands,
                policy: ReleasePolicy(platform: HostPlatform(architecture: .arm64, osMajor: 27)),
                minimumMacOS: .jerdKitMinimum)
        }
    }

    @Test func aBuildForANewerMacOSIsRefusedAndNothingIsInstalled() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try Fixture(builtFor: MinimumMachO.twentySeven)
        let message =
            "The Redis build does not run on macOS 14.0, the oldest macOS that Jerd supports: "
            + "bin/redis-cli needs macOS 27.0; bin/redis-server needs macOS 27.0. Jerd installed nothing."
        await #expect(throws: JerdError.invalid(message)) {
            try await fixture.installer(folder).install(fixture.release)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path).isEmpty)
    }

    @Test func aBuildForTheAppMinimumIsInstalledAndMakeGetsTheTarget() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try Fixture(builtFor: MinimumMachO.fourteen)
        let runtime = try await fixture.installer(folder).install(fixture.release)
        #expect(runtime.version == "8.8.3")
        let make = try #require(fixture.commands.requests.first { $0.executable.lastPathComponent == "make" })
        #expect(make.environment["MACOSX_DEPLOYMENT_TARGET"] == "14.0")
        #expect(make.environment["CFLAGS"] == "-arch arm64 -mmacosx-version-min=14.0")
        #expect(make.environment["LDFLAGS"] == "-arch arm64 -mmacosx-version-min=14.0")
    }
}
