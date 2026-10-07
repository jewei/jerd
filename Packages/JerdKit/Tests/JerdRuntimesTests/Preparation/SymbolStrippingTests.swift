import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess
import JerdRuntimes
import Testing

@Suite struct SymbolStrippingTests {
    private func context(
        _ folder: TemporaryFolder, kind: RuntimeKind, version: String, commands: ScriptedCommandRunner
    ) throws -> PreparationContext {
        let release = RuntimeRelease(
            kind: kind, version: version, artifact: .archive(try .runtime("https://github.com/a/b"), size: .exact(1)),
            archiveSHA256: digest("a"), releasePage: try .runtime("https://github.com/a"), architecture: .arm64)
        try OwnedDirectory.create(folder.path("payload"))
        return PreparationContext(
            release: release, artifact: nil, payload: folder.path("payload"), staging: folder.url,
            tools: PreparationTools(), commands: commands, fetcher: FakeFetcher(), minimumMacOS: .jerdKitMinimum)
    }

    private func names(_ kind: RuntimeKind, _ version: String = "1.0.0") throws -> [String] {
        try SymbolStripping.executables(for: kind, version: version).map(\.string)
    }

    @Test func theRuleNamesTheEmbeddedExecutablesWithLocalSymbolsOnly() throws {
        #expect(try names(.php, "8.5.11") == ["php-native-8.5", "php-native-fpm-8.5"])
        #expect(try names(.mailpit) == ["mailpit"])
        #expect(try names(.redis) == ["bin/redis-server", "bin/redis-cli"])
        for kind in [RuntimeKind.caddy, .cloudflared, .composer, .laravel, .mysql, .postgresql, .rustfs] {
            #expect(try names(kind).isEmpty, "\(kind)")
        }
        #expect(SymbolStripping.strip.path == "/usr/bin/strip")
        #expect(SymbolStripping.arguments == ["-x"])
    }

    @Test func requiredStrippingStripsAndVerifiesEachFileInOrder() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let commands = ScriptedCommandRunner()
        let context = try context(folder, kind: .redis, version: "8.8.3", commands: commands)
        try folder.write("server", to: "payload/bin/redis-server", mode: 0o700)
        try folder.write("cli", to: "payload/bin/redis-cli", mode: 0o700)
        try await SymbolStripper(context: context, requirement: .required).strip()
        let server = context.payload.appendingPathComponent("bin/redis-server").path
        let cli = context.payload.appendingPathComponent("bin/redis-cli").path
        #expect(
            commands.commandLines == [
                ["strip", "-x", server], ["codesign", "--verify", "--strict", server],
                ["strip", "-x", cli], ["codesign", "--verify", "--strict", cli],
            ])
        #expect(commands.requests.map(\.executable.path).first == "/usr/bin/strip")
    }

    @Test func aBrokenSignatureAfterStrippingStopsThePreparation() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let commands = ScriptedCommandRunner { request in
            CommandResult(status: request.executable.lastPathComponent == "codesign" ? 1 : 0, output: "invalid")
        }
        let context = try context(folder, kind: .mailpit, version: "1.31.3", commands: commands)
        try folder.write("mailpit", to: "payload/mailpit", mode: 0o700)
        let path = try #require(RelativePath("mailpit"))
        await #expect(throws: SymbolStripping.brokenSignature(path, kind: .mailpit)) {
            try await SymbolStripper(context: context, requirement: .required).strip()
        }
    }

    @Test func aMissingExecutableFailsClearly() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let commands = ScriptedCommandRunner()
        let context = try context(folder, kind: .mailpit, version: "1.31.3", commands: commands)
        await #expect(throws: JerdError.invalid("The Mailpit package does not contain mailpit.")) {
            try await SymbolStripper(context: context, requirement: .required).strip()
        }
        #expect(commands.commandLines.isEmpty)
    }

    @Test func withoutDeveloperToolsTheAppKeepsTheFilesAsTheyAre() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let commands = ScriptedCommandRunner { _ in
            CommandResult(status: 2, output: "xcode-select: error: unable to get active developer directory")
        }
        let context = try context(folder, kind: .php, version: "8.5.11", commands: commands)
        try await SymbolStripper(context: context, requirement: .whenDeveloperToolsExist).strip()
        #expect(commands.commandLines == [["xcode-select", "-p"]])
    }

    @Test func aDeveloperFolderThatIsGoneIsTreatedAsNoTools() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let gone = folder.path("Developer").path
        let commands = ScriptedCommandRunner { _ in CommandResult(status: 0, output: "\(gone)\n") }
        let context = try context(folder, kind: .php, version: "8.5.11", commands: commands)
        try await SymbolStripper(context: context, requirement: .whenDeveloperToolsExist).strip()
        #expect(commands.commandLines == [["xcode-select", "-p"]])
    }

    @Test func withDeveloperToolsTheAppStripsToo() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try OwnedDirectory.create(folder.path("Developer"))
        let developer = folder.path("Developer").path
        let commands = ScriptedCommandRunner { request in
            CommandResult(status: 0, output: request.executable.lastPathComponent == "xcode-select" ? developer : "")
        }
        let context = try context(folder, kind: .mailpit, version: "1.31.3", commands: commands)
        try folder.write("mailpit", to: "payload/mailpit", mode: 0o700)
        try await SymbolStripper(context: context, requirement: .whenDeveloperToolsExist).strip()
        #expect(commands.commandLines.map(\.first) == ["xcode-select", "strip", "codesign"])
    }

    @Test func aKindWithoutStrippedFilesRunsNoCommand() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let commands = ScriptedCommandRunner()
        let context = try context(folder, kind: .caddy, version: "2.11.4", commands: commands)
        try await SymbolStripper(context: context, requirement: .whenDeveloperToolsExist).strip()
        try await SymbolStripper(context: context, requirement: .required).strip()
        #expect(commands.commandLines.isEmpty)
    }
}
