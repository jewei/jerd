import Foundation
import Testing
@testable import JerdCore

@Suite struct RuntimeUpdateTests {
    @Test func versionOrderingAndUnstableVersions() throws {
        #expect(try #require(RuntimeVersion("8.10.2")) > #require(RuntimeVersion("8.8.3")))
        #expect(RuntimeVersion("v8.5.11") == RuntimeVersion("8.5.11.0"))
        for value in ["8.6.0RC1", "8.6.0-beta", "../8.6", "8..6", "8.6 ", "99999999999.1"] { #expect(RuntimeVersion(value) == nil) }
    }
    @Test func downloadBoundaries() throws {
        try RuntimeDownload.validate(URL(string: "https://github.com/lerd-env/php/releases")!)
        for value in ["http://github.com/a", "https://github.com.evil.test/a", "https://name:password@github.com/a", "https://github.com:8443/a", "file:///tmp/runtime"] {
            #expect(throws: (any Error).self) { try RuntimeDownload.validate(URL(string: value)!) }
        }
        #expect(RuntimeDownload.validSHA256(String(repeating: "a", count: 64)))
        #expect(!RuntimeDownload.validSHA256(String(repeating: "g", count: 64)))
    }
    @Test func extractsRegularFilesAndMaterializesInternalLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-archive-test-\(UUID())")
        try PrivateFiles.directory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("test.tar"), target = root.appendingPathComponent("out")
        try tar([("root/bin/tool", "0", "", Data("hello".utf8)),
                 ("root/bin/alias", "2", "tool", Data()),
                 ("root/bin/hard", "1", "root/bin/tool", Data())]).write(to: source)
        try RuntimeArchive.extract(source, to: target, stripRoot: true)
        for name in ["tool", "alias", "hard"] {
            let file = target.appendingPathComponent("bin/\(name)")
            #expect(try String(contentsOf: file, encoding: .utf8) == "hello")
            #expect(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
        }
    }
    @Test func rejectsUnsafeArchiveEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-archive-test-\(UUID())")
        try PrivateFiles.directory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let cases: [[(String, String, String, Data)]] = [
            [("../escape", "0", "", Data())], [("/absolute", "0", "", Data())],
            [("root/link", "2", "../../escape", Data())], [("root/link", "1", "/tmp/escape", Data())],
            [("root/fifo", "6", "", Data())],
            [("root/a", "2", "b", Data()), ("root/b", "2", "a", Data())],
            [("root/file", "0", "", Data()), ("root/FILE", "0", "", Data())]
        ]
        for (index, entries) in cases.enumerated() {
            let source = root.appendingPathComponent("\(index).tar")
            try tar(entries).write(to: source)
            #expect(throws: (any Error).self) { try RuntimeArchive.extract(source, to: root.appendingPathComponent("out-\(index)"), stripRoot: true) }
        }
    }
    @Test func rejectsMalformedPublisherSignatures() throws {
        for value in ["", "not a signature", "-----BEGIN PGP SIGNATURE-----\nAAAA\n-----END PGP SIGNATURE-----"] {
            #expect(throws: (any Error).self) {
                try MySQLSignature.verify(archive: URL(fileURLWithPath: "/nonexistent"), armoredSignature: Data(value.utf8))
            }
        }
    }
    @Test func interruptedServiceUpdateRestoresDataAndKeepsFailedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-backup-test-\(UUID())")
        try PrivateFiles.directory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = root.appendingPathComponent("data"), settings = root.appendingPathComponent("settings.json")
        try PrivateFiles.directory(data)
        try PrivateFiles.write(Data("original".utf8), to: data.appendingPathComponent("object"))
        try PrivateFiles.write(Data("old runtime".utf8), to: settings)
        let transaction = ServiceUpdateBackup(root: root, names: ["settings.json", "data", "new-file"])
        let backup = try transaction.begin()
        try PrivateFiles.write(Data("changed".utf8), to: data.appendingPathComponent("object"))
        try PrivateFiles.write(Data("new runtime".utf8), to: settings)
        try PrivateFiles.write(Data("created".utf8), to: root.appendingPathComponent("new-file"))
        let reloaded = ServiceUpdateBackup(root: root, names: ["settings.json", "data", "new-file"])
        try reloaded.restoreIfNeeded()
        #expect(try String(contentsOf: data.appendingPathComponent("object"), encoding: .utf8) == "original")
        #expect(try String(contentsOf: settings, encoding: .utf8) == "old runtime")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("new-file").path))
        #expect(!reloaded.isPending)
        #expect(try FileManager.default.contentsOfDirectory(atPath: backup.path).contains { $0.hasPrefix("failed-attempt-") })
        try reloaded.restoreIfNeeded()
    }
    @Test func bootstrapPreservesConfiguredToolsAndRejectsCorruptRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-bootstrap-test-\(UUID())")
        try PrivateFiles.directory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = BundledRuntimes()
        var config = AppConfiguration()
        #expect(try await bundle.needsBootstrap(configuration: config, directory: root))
        let file = root.appendingPathComponent("cli-tools.json")
        let broken = Data("broken tools record".utf8)
        try PrivateFiles.write(broken, to: file)
        await #expect(throws: (any Error).self) { try await bundle.needsBootstrap(configuration: config, directory: root) }
        #expect(try Data(contentsOf: file) == broken)
        let companions = CLICompanions(composerPath: "/updated/composer.phar", laravelPath: "/updated/laravel",
            composerVersion: "2.10.3", laravelVersion: "5.32.0")
        try PrivateFiles.write(JSONEncoder().encode(companions), to: file)
        config.caddy = CaddyRuntime(path: "/updated/caddy", version: "v2.11.6", architectures: [.arm64])
        config.runtimes = [DevelopmentRuntime(cliPath: "/updated/php", fpmPath: "/updated/php-fpm", version: "8.5.11",
            architectures: [.arm64], cliExtensions: [], fpmExtensions: [])]
        #expect(try await !bundle.needsBootstrap(configuration: config, directory: root))
    }
    @Test(arguments: [false, true]) func postgresAlwaysDetachesAfterCancellationOrFailure(failDetach: Bool) async throws {
        actor Commands: CommandRunning {
            let failDetach: Bool
            var detaches = 0
            var cleanupWasCancelled = false
            init(failDetach: Bool) { self.failDetach = failDetach }
            func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
                if request.arguments.first == "attach" {
                    let mount = URL(fileURLWithPath: request.arguments[4])
                    let app = mount.appendingPathComponent("Postgres.app")
                    for name in ["bin", "lib", "share"] { try PrivateFiles.directory(app.appendingPathComponent("Contents/Versions/18/\(name)")) }
                    try PrivateFiles.directory(app.appendingPathComponent("Contents/Resources"))
                    try PrivateFiles.write(Data("credits".utf8), to: app.appendingPathComponent("Contents/Resources/Credits.rtf"))
                    if !failDetach { withUnsafeCurrentTask { $0?.cancel() }; throw CancellationError() }
                }
                if request.arguments.first == "detach" {
                    detaches += 1
                    if failDetach, detaches == 1 { throw JerdError.process("Test detach failure") }
                    cleanupWasCancelled = Task.isCancelled
                }
                return CommandResult(status: 0, output: "")
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-mount-test-\(UUID())")
        try PrivateFiles.directory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = root.appendingPathComponent("payload")
        try PrivateFiles.directory(payload)
        let commands = Commands(failDetach: failDetach)
        let installer = RuntimeInstaller(directory: root, commands: commands)
        let task = Task { try await installer.preparePostgres(root.appendingPathComponent("test.dmg"), payload: payload, staging: root) }
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(await commands.detaches == (failDetach ? 2 : 1))
        #expect(await commands.cleanupWasCancelled == false)
    }
    private func tar(_ entries: [(String, String, String, Data)]) -> Data {
        var result = Data()
        for (name, type, link, data) in entries {
            var header = [UInt8](repeating: 0, count: 512)
            func field(_ value: String, _ offset: Int) {
                for (index, byte) in value.utf8.enumerated() { header[offset + index] = byte }
            }
            field(name, 0); field("0000700", 100); field("0000000", 108); field("0000000", 116)
            field(String(format: "%011o", data.count), 124); field("00000000000", 136)
            field("        ", 148); field(type, 156); field(link, 157); field("ustar", 257); field("00", 263)
            let checksum = header.reduce(0) { $0 + Int($1) }
            field(String(format: "%06o", checksum), 148); header[154] = 0; header[155] = 32
            result.append(contentsOf: header); result.append(data)
            if data.count % 512 != 0 { result.append(Data(repeating: 0, count: 512 - data.count % 512)) }
        }
        result.append(Data(repeating: 0, count: 1024))
        return result
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["JERD_UPDATE_INTEGRATION"] == "1"))
struct RuntimeUpdateIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_UPDATE_INSTALL"] == "1"))
    func installRealPackages() async throws {
        let environment = ProcessInfo.processInfo.environment
        let destination = URL(fileURLWithPath: try #require(environment["JERD_UPDATE_DESTINATION"]))
        let installer = RuntimeInstaller(directory: destination)
        let configuration = try await JSONConfigurationStore(directory: JSONConfigurationStore.applicationDirectory).load()
        let php = configuration.runtimes.first { $0.id == configuration.defaultRuntimeID }
        let companions = try JSONDecoder().decode(CLICompanions.self, from: Data(contentsOf: JSONConfigurationStore.applicationDirectory.appendingPathComponent("runtimes/cli-tools.json")))
        let catalog = RuntimeUpdateCatalog()
        let kinds = environment["JERD_UPDATE_KINDS"]?.split(separator: ",").compactMap { RuntimeKind(rawValue: String($0)) } ?? RuntimeKind.allCases
        for kind in kinds {
            let check = await catalog.check(kind)
            let release = try #require(kind == .php ? check.releases.first { $0.version == "8.4.26" } : check.releases.first, "\(kind): \(check.error ?? "")")
            let result = try await installer.install(release, php: php, companions: companions) { progress in
                if progress.fraction == nil { print("\(kind.title): \(progress.message)") }
            }
            #expect(FileManager.default.fileExists(atPath: result.executable.path))
            #expect(result.kind == kind)
            print("Installed and inspected \(kind.title) \(result.version)")
            if let engine = DatabaseEngine(rawValue: kind.rawValue) {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-updated-database-\(UUID())")
                defer { try? FileManager.default.removeItem(at: root) }
                let manager = DatabaseManager(directory: root)
                _ = try await manager.load()
                let runtime = DatabaseRuntime(id: result.directory.lastPathComponent, engine: engine, version: result.version, path: result.directory.path)
                try await manager.registerRuntimes([runtime])
                let service = try await manager.add(name: "Updated \(engine.title)", runtimeID: runtime.id, port: manager.suggestedPort(for: engine))
                do {
                    try await manager.start(service.id)
                    #expect(await manager.snapshot().statuses[service.id]?.state == .running)
                    let paths = DatabasePaths(directory: root, serviceID: service.id)
                    let credentials = try JSONDecoder().decode(DatabaseCredentials.self, from: Data(contentsOf: paths.credentials))
                    let response = try await LocalCommandRunner().run(DatabaseDriver.healthCheck(runtime: runtime, service: service,
                        paths: paths, credentials: credentials), timeout: .seconds(5))
                    #expect(response.status == 0)
                    try await manager.stop(service.id)
                    try await manager.start(service.id)
                    #expect(await manager.snapshot().statuses[service.id]?.state == .running)
                    try await manager.stop(service.id)
                } catch { try? await manager.stop(service.id); throw error }
                print("Started, queried, and restarted updated \(engine.title) \(result.version)")
            }
        }
        #expect(try await installer.installed().count >= kinds.count)
    }
    @Test func liveCatalog() async throws {
        let catalog = RuntimeUpdateCatalog()
        for kind in RuntimeKind.allCases {
            let check = await catalog.check(kind)
            #expect(check.error == nil, "\(kind.title): \(check.error ?? "")")
            #expect(!check.releases.isEmpty)
            print("\(kind.title): \(check.releases.first?.version ?? "unavailable")")
        }
    }
    @Test func mysqlPublisherSignature() throws {
        let path = try #require(ProcessInfo.processInfo.environment["JERD_MYSQL_ARCHIVE"])
        let archive = URL(fileURLWithPath: path)
        let signature = try Data(contentsOf: URL(fileURLWithPath: path + ".asc"))
        try MySQLSignature.verify(archive: archive, armoredSignature: signature)
        let fake = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-signature-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: fake) }
        try Data("changed archive".utf8).write(to: fake)
        #expect(throws: (any Error).self) { try MySQLSignature.verify(archive: fake, armoredSignature: signature) }
    }
}
