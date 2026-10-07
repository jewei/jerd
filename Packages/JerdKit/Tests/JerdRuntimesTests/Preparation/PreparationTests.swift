import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess
import JerdRuntimes
import Testing
import os

@Suite struct PreparationTests {
    private func context(
        _ folder: TemporaryFolder, kind: RuntimeKind, version: String = "1.0.0", artifact: URL? = nil,
        tools: PreparationTools = PreparationTools(), commands: ScriptedCommandRunner = ScriptedCommandRunner(),
        fetcher: FakeFetcher = FakeFetcher()
    ) throws -> PreparationContext {
        let release = RuntimeRelease(
            kind: kind, version: version, artifact: .archive(try .runtime("https://github.com/a/b"), size: .exact(1)),
            archiveSHA256: digest("a"), releasePage: try .runtime("https://github.com/a"), architecture: .arm64)
        try OwnedDirectory.create(folder.path("payload"))
        return PreparationContext(
            release: release, artifact: artifact, payload: folder.path("payload"), staging: folder.url, tools: tools,
            commands: commands, fetcher: fetcher, minimumMacOS: .jerdKitMinimum)
    }

    @Test func phpTakesTheBranchExecutablesAndNotices() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var tar = TarBuilder()
        for name in ["php-native-8.4", "php-native-fpm-8.4"] { tar.file(name, "bin", mode: "0000755") }
        for name in ["THIRD-PARTY-NOTICES.txt", "BUILD-INFO.txt", "php-native-8.5", "lib/ext.so"] {
            tar.file(name, "x")
        }
        try tar.write(to: folder.path("download"))
        let context = try context(folder, kind: .php, version: "8.4.26", artifact: folder.path("download"))
        try await PHPPreparer().prepare(context)
        let names = try FileManager.default.contentsOfDirectory(atPath: context.payload.path).sorted()
        #expect(names == ["BUILD-INFO.txt", "THIRD-PARTY-NOTICES.txt", "php-native-8.4", "php-native-fpm-8.4"])
    }

    @Test func archiveWithoutTheExpectedBinaryFailsClearly() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("LICENSE", "text")
        try tar.write(to: folder.path("download"))
        let context = try context(folder, kind: .caddy, version: "2.11.4", artifact: folder.path("download"))
        await #expect(throws: JerdError.invalid("The Caddy package does not contain caddy.")) {
            try await SingleBinaryPreparer().prepare(context)
        }
    }

    @Test func redisWithoutTheCommandLineToolsNamesTheStepThatFixesIt() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("redis-8.8.3/src/server.c", "int main(void) { return 0; }")
        try tar.write(to: folder.path("download"))
        let commands = ScriptedCommandRunner { request in
            CommandResult(status: request.executable.lastPathComponent == "xcrun" ? 1 : 0, output: "no developer tools")
        }
        let context = try context(
            folder, kind: .redis, version: "8.8.3", artifact: folder.path("download"), commands: commands)
        await #expect(throws: RedisSourceBuilder.missingCompiler) { try await RedisSourceBuilder().prepare(context) }
        #expect(commands.commandLines == [["xcrun", "--find", "clang"]])
    }

    @Test func redisNoticesKeepTheSourceFilesButNoBuildOutput() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("redis-8.8.3/src/server.c", "int main(void) { return 0; }")
        tar.file("redis-8.8.3/COPYING", "license")
        tar.file("redis-8.8.3/deps/lua/COPYRIGHT", "Lua license")
        tar.file("redis-8.8.3/deps/lua/src/lua.c", "int main(void) { return 0; }")
        tar.file("redis-8.8.3/deps/hiredis/test.sh", "#!/bin/sh", mode: "0000755")
        tar.file("redis-8.8.3/deps/xxhash/LICENSE", "xxHash license")
        tar.file("redis-8.8.3/deps/prebuilt.a", "archive")
        try tar.write(to: folder.path("download"))
        // The fake build writes what the Redis build writes: the binaries, the Lua tools, objects, and
        // dependency files.
        let commands = ScriptedCommandRunner { request in
            guard request.executable.lastPathComponent == "make" else { return CommandResult(status: 0, output: "") }
            let src = request.workingDirectory
            let deps = src.deletingLastPathComponent().appendingPathComponent("deps")
            let outputs = [
                src.appendingPathComponent("redis-server"), src.appendingPathComponent("redis-cli"),
                deps.appendingPathComponent("lua/src/lua"), deps.appendingPathComponent("lua/src/luac"),
                deps.appendingPathComponent("lua/src/lua.o"), deps.appendingPathComponent("lua/src/liblua.a"),
                deps.appendingPathComponent("xxhash/cachedObjs/1a2b/xxhash.d"),
            ]
            for file in outputs {
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: file)
            }
            return CommandResult(status: 0, output: "")
        }
        let context = try context(
            folder, kind: .redis, version: "8.8.3", artifact: folder.path("download"), commands: commands)
        try await RedisSourceBuilder().prepare(context)
        let notices = context.payload.appendingPathComponent(RedisSourceBuilder.dependencyNoticesFolder)
        let files = try #require(FileManager.default.subpaths(atPath: notices.path)).filter { path in
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: notices.appendingPathComponent(path).path, isDirectory: &isFolder)
            return !isFolder.boolValue
        }
        #expect(files.sorted() == ["hiredis/test.sh", "lua/COPYRIGHT", "lua/src/lua.c", "xxhash/LICENSE"])
        let payload = try FileManager.default.contentsOfDirectory(atPath: context.payload.path).sorted()
        #expect(payload == ["COPYING", "bin", RedisSourceBuilder.dependencyNoticesFolder])
    }

    @Test func laravelNeedsPHPAndComposer() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let context = try context(folder, kind: .laravel, version: "5.32.0")
        await #expect(throws: JerdError.unavailable("Install PHP and Composer before the Laravel installer.")) {
            try await LaravelComposerResolver().prepare(context)
        }
    }

    @Test func laravelRunsComposerWithAPrivateHomeOutsideThePayload() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let commands = ScriptedCommandRunner()
        let tools = PreparationTools(phpCLI: URL(fileURLWithPath: "/php"), composer: URL(fileURLWithPath: "/c.phar"))
        let context = try context(folder, kind: .laravel, version: "5.32.0", tools: tools, commands: commands)
        try await LaravelComposerResolver().prepare(context)
        let request = try #require(commands.requests.first)
        #expect(request.executable.path == "/php")
        #expect(request.arguments.prefix(3) == ["-n", "/c.phar", "update"])
        #expect(request.workingDirectory == context.payload)
        let home = try #require(request.environment["HOME"])
        #expect(!home.hasPrefix(context.payload.path) && home.hasPrefix(folder.url.path))
        #expect(request.environment["PHP_INI_SCAN_DIR"] == "")
        #expect(FileProbe.presence(at: context.payload.appendingPathComponent("composer.json")) == .present)
    }

    @Test func laravelPreparationPrunesTheVendorFolderAfterComposer() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let commands = ScriptedCommandRunner { request in
            let vendor = request.workingDirectory.appendingPathComponent("vendor/laravel/installer")
            try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
            for name in ["README.md", "LICENSE.md", "composer.json"] {
                try Data("x".utf8).write(to: vendor.appendingPathComponent(name))
            }
            return CommandResult(status: 0, output: "")
        }
        let tools = PreparationTools(phpCLI: URL(fileURLWithPath: "/php"), composer: URL(fileURLWithPath: "/c.phar"))
        let context = try context(
            folder, kind: .laravel, version: "5.32.0", tools: tools, commands: commands)
        try await LaravelComposerResolver().prepare(context)
        let package = context.payload.appendingPathComponent("vendor/laravel/installer")
        #expect(FileProbe.presence(at: package.appendingPathComponent("README.md")) == .absent)
        #expect(FileProbe.presence(at: package.appendingPathComponent("LICENSE.md")) == .present)
        #expect(FileProbe.presence(at: package.appendingPathComponent("composer.json")) == .present)
    }

    @Test(arguments: [false, true])
    func postgresImageIsAlwaysDetachedAfterCancellationOrFailure(failDetach: Bool) async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let detaches = OSAllocatedUnfairLock(initialState: (count: 0, cancelled: false))
        let commands = ScriptedCommandRunner { request in
            if request.arguments.first == "attach", !failDetach {
                withUnsafeCurrentTask { $0?.cancel() }
                throw CancellationError()
            }
            if request.arguments.first == "eject" {
                let count = detaches.withLock {
                    $0.count += 1
                    $0.cancelled = Task.isCancelled
                    return $0.count
                }
                if failDetach, count == 1 { throw JerdError.processFailed("Test detach failure") }
            }
            return CommandResult(status: 0, output: "")
        }
        try folder.write("dmg", to: "test.dmg")
        let context = try context(folder, kind: .postgresql, artifact: folder.path("test.dmg"), commands: commands)
        let mount = folder.path("volume")
        let task = Task {
            try await DiskImageMount(context: context).withVerifiedApp(
                image: folder.path("test.dmg"), mountPoint: mount, app: "Postgres.app", requirement: .postgresApp
            ) { _ in }
        }
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(detaches.withLock { $0.count } == (failDetach ? 2 : 1))
        #expect(detaches.withLock { $0.cancelled } == false)
    }

    @Test func unsignedPostgresAppIsRefusedAndDetached() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let commands = ScriptedCommandRunner { request in
            CommandResult(status: request.executable.lastPathComponent == "codesign" ? 3 : 0, output: "not satisfied")
        }
        let context = try context(folder, kind: .postgresql, commands: commands)
        await #expect(throws: JerdError.self) {
            try await DiskImageMount(context: context).withVerifiedApp(
                image: folder.path("x.dmg"), mountPoint: folder.path("volume"), app: "Postgres.app",
                requirement: .postgresApp
            ) { _ in }
        }
        #expect(commands.commandLines.map(\.[1]) == ["attach", "--verify", "eject"])
    }

    /// The image is ejected with `diskutil eject <mount point>`, not the deprecated `hdiutil detach`.
    @Test func verifiedImageIsEjectedWithDiskutilAfterTheCopy() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let commands = ScriptedCommandRunner()
        let context = try context(folder, kind: .postgresql, commands: commands)
        let image = folder.path("x.dmg")
        let mount = folder.path("volume")
        let copied = try await DiskImageMount(context: context).withVerifiedApp(
            image: image, mountPoint: mount, app: "Postgres.app", requirement: .postgresApp
        ) { app in app.lastPathComponent }
        #expect(copied == "Postgres.app")
        let paths = commands.requests.map(\.executable.path)
        #expect(paths == ["/usr/bin/hdiutil", "/usr/bin/codesign", "/usr/sbin/diskutil"])
        #expect(
            commands.requests.first?.arguments == [
                "attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, image.path,
            ])
        #expect(commands.requests.last?.arguments == ["eject", mount.path])
    }

    @Test func rustfsWithHomebrewLZMAGetsTheBundledLibrary() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let library = try folder.write("lzma", to: "support/liblzma.5.dylib")
        let license = try folder.write("0BSD", to: "support/COPYING.0BSD")
        let commands = ScriptedCommandRunner()
        let tools = PreparationTools(lzma: SupportLibrary(library: library, license: license))
        let context = try context(folder, kind: .rustfs, tools: tools, commands: commands)
        let binary = context.payload.appendingPathComponent("rustfs")
        try MachOBuilder.thin(libraries: ["/usr/lib/libSystem.B.dylib", MachOLoadCommandsTests.homebrew]).write(
            to: binary)
        try await LZMALinker(context: context).bundleLibraryIfNeeded(for: binary)
        let names = try MachOLoadCommands.libraries(in: Data(contentsOf: binary)).map(\.name)
        #expect(names == ["/usr/lib/libSystem.B.dylib", "@loader_path/liblzma.5.dylib"])
        #expect(permissions(binary) == 0o700)
        #expect(permissions(context.payload.appendingPathComponent("liblzma.5.dylib")) == 0o600)
        #expect(FileProbe.presence(at: context.payload.appendingPathComponent("XZ-LICENSE.txt")) == .present)
        #expect(commands.commandLines == [["codesign", "--force", "--sign", "-", binary.path]])
    }

    @Test func rustfsThatNeedsLZMAWithoutTheBundledLibraryIsRefused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let context = try context(folder, kind: .rustfs)
        let binary = context.payload.appendingPathComponent("rustfs")
        try MachOBuilder.thin(libraries: [MachOLoadCommandsTests.homebrew]).write(to: binary)
        await #expect(throws: JerdError.self) {
            try await LZMALinker(context: context).bundleLibraryIfNeeded(for: binary)
        }
        try MachOBuilder.thin(libraries: ["/usr/local/lib/libssl.dylib"]).write(to: binary)
        await #expect(
            throws: JerdError.invalid(
                "This RustFS release needs /usr/local/lib/libssl.dylib, which Jerd cannot supply.")
        ) {
            try await LZMALinker(context: context).bundleLibraryIfNeeded(for: binary)
        }
    }

    @Test func rustfsWithOnlySystemLibrariesIsUnchanged() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let commands = ScriptedCommandRunner()
        let context = try context(folder, kind: .rustfs, commands: commands)
        let binary = context.payload.appendingPathComponent("rustfs")
        let original = MachOBuilder.thin(libraries: ["/usr/lib/libSystem.B.dylib"])
        try original.write(to: binary)
        try await LZMALinker(context: context).bundleLibraryIfNeeded(for: binary)
        #expect(try Data(contentsOf: binary) == original)
        #expect(commands.requests.isEmpty)
    }
}
