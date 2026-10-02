import Foundation
import Testing
import Darwin
@testable import JerdCore

func temporaryDirectory(_ suffix: String = "") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-tests-\(UUID().uuidString)\(suffix)")
    try PrivateFiles.directory(url)
    return url
}

func makeSite(_ root: URL, hostname: String = "demo.test") -> Site {
    Site(displayName: "Demo", projectPath: root.path, documentRoot: root.path, hostname: hostname)
}

func sampleRuntime(id: UUID = UUID()) -> DevelopmentRuntime {
    DevelopmentRuntime(id: id, cliPath: "/local/php", fpmPath: "/local/php-fpm", version: "8.4.0",
                       architectures: [.current], cliExtensions: ["Core", "json"], fpmExtensions: ["Core", "json"])
}

struct SiteTests {
    @Test func validHostnames() throws {
        #expect(try Hostname.validate("SHOP.Example.test") == "shop.example.test")
        #expect(try Hostname.validate("my-site2.test") == "my-site2.test")
    }

    @Test(arguments: ["test", "example.com", "*.test", "-site.test", "site-.test", "foo..test",
                      "foo.test:443", " foo.test", "foo.test.", "café.test", "a_b.test", "a/test",
                      String(repeating: "a", count: 64) + ".test", "foo.test\n"])
    func invalidHostnames(_ hostname: String) {
        #expect(throws: (any Error).self) { try Hostname.validate(hostname) }
    }

    @Test func hostsConflicts() {
        #expect(HostsFile.hasConflict(hostname: "shop.test", contents: "127.0.0.1 shop.test # another tool"))
        #expect(HostsFile.hasConflict(hostname: "shop.test", contents: "10.0.0.2 alias SHOP.test"))
        #expect(!HostsFile.hasConflict(hostname: "shop.test", contents: "# shop.test\n127.0.0.1 other.test"))
        #expect(!HostsFile.hasConflict(hostname: "shop.test", contents: "# BEGIN JERD\n127.0.0.1 shop.test\n# END JERD"))
        #expect(HostsFile.hasConflict(hostname: "shop.test", contents: "# BEGIN JERD\n10.1.1.1 shop.test\n# END JERD"))
    }

    @Test func documentRootsAndUnicode() throws {
        let directory = try temporaryDirectory(" café 项目")
        defer { try? FileManager.default.removeItem(at: directory) }
        let validator = SiteValidator()
        let canonical = directory.resolvingSymlinksInPath()
        let plain = try validator.suggestDocumentRoot(projectPath: directory.path)
        #expect(plain.path == canonical.path)
        #expect(plain.requiresConfirmation)
        #expect(throws: (any Error).self) {
            try validator.validate(makeSite(directory), existing: [], documentRootConfirmed: false)
        }
        let accepted = try validator.validate(makeSite(directory), existing: [], documentRootConfirmed: true)
        #expect(accepted.projectPath == canonical.path)
        let publicDirectory = directory.appendingPathComponent("public")
        try PrivateFiles.directory(publicDirectory)
        for name in ["artisan", "composer.json", "public/index.php"] {
            try Data("not executable".utf8).write(to: directory.appendingPathComponent(name))
        }
        let laravel = try validator.suggestDocumentRoot(projectPath: directory.path)
        #expect(laravel.isLaravel)
        #expect(laravel.path == canonical.appendingPathComponent("public").path)
        var draft = makeSite(directory)
        draft.documentRoot = publicDirectory.path
        _ = try validator.validate(draft, existing: [], documentRootConfirmed: false)
        draft.documentRoot = directory.appendingPathComponent("missing").path
        #expect(throws: (any Error).self) { try validator.validate(draft, existing: [], documentRootConfirmed: true) }
        draft.documentRoot = directory.deletingLastPathComponent().path
        #expect(throws: (any Error).self) { try validator.validate(draft, existing: [], documentRootConfirmed: true) }
        let outside = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = directory.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        draft.documentRoot = link.path
        #expect(throws: (any Error).self) { try validator.validate(draft, existing: [], documentRootConfirmed: true) }
    }

    @Test func duplicatesAndEditing() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let validator = SiteValidator()
        let first = try validator.validate(makeSite(root), existing: [], documentRootConfirmed: true)
        #expect(throws: (any Error).self) {
            try validator.validate(makeSite(root, hostname: "other.test"), existing: [first], documentRootConfirmed: true)
        }
        var edited = first
        edited.displayName = "New name"
        #expect(try validator.validate(edited, existing: [first], documentRootConfirmed: true).displayName == "New name")
        let link = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        #expect(throws: (any Error).self) {
            try validator.validate(makeSite(link, hostname: "alias.test"), existing: [first], documentRootConfirmed: true)
        }
        let otherProject = root.appendingPathComponent("second")
        try PrivateFiles.directory(otherProject)
        #expect(throws: (any Error).self) {
            try validator.validate(makeSite(otherProject), existing: [first], documentRootConfirmed: true)
        }
    }
}

struct PersistenceTests {
    @Test func roundTripBackupAndRemoval() async throws {
        let root = try temporaryDirectory(" storage café")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        try PrivateFiles.directory(project)
        let marker = project.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: marker)
        let store = JSONConfigurationStore(directory: root)
        #expect(try await store.load() == AppConfiguration())
        var configuration = AppConfiguration()
        configuration.sites = [makeSite(project)]
        configuration.runtimes = [sampleRuntime()]
        configuration.defaultRuntimeID = configuration.runtimes[0].id
        try await store.save(configuration)
        #expect(try await store.load() == configuration)
        let old = try Data(contentsOf: root.appendingPathComponent("configuration.json"))
        configuration.sites.removeAll()
        try await store.save(configuration)
        #expect(try Data(contentsOf: root.appendingPathComponent("configuration.previous.json")) == old)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("configuration.json").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test(arguments: ["broken json", "{\"schemaVersion\":999}", "{\"schemaVersion\":1}"])
    func corruptDataIsPreserved(_ contents: String) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("configuration.json")
        let data = Data(contents.utf8)
        try data.write(to: url)
        let store = JSONConfigurationStore(directory: root)
        await #expect(throws: (any Error).self) { try await store.load() }
        await #expect(throws: (any Error).self) { try await store.save(AppConfiguration()) }
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func migration() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{\"schemaVersion\":0,\"sites\":[]}".utf8).write(to: root.appendingPathComponent("configuration.json"))
        let store = JSONConfigurationStore(directory: root)
        #expect(try await store.load().schemaVersion == 1)
    }
}

struct RuntimeTests {
    @Test func defaultAndPinnedResolution() throws {
        var configuration = AppConfiguration()
        let first = sampleRuntime()
        let second = sampleRuntime()
        configuration.runtimes = [first, second]
        configuration.defaultRuntimeID = first.id
        var site = makeSite(URL(fileURLWithPath: "/project"))
        #expect(try configuration.runtime(for: site).id == first.id)
        site.phpSelection = .pinned(second.id)
        #expect(try configuration.runtime(for: site).id == second.id)
        configuration.sites = [site]
        #expect(throws: (any Error).self) { try configuration.removeRuntime(first.id) }
        #expect(throws: (any Error).self) { try configuration.removeRuntime(second.id) }
        configuration.runtimes.removeLast()
        #expect(throws: (any Error).self) { try configuration.runtime(for: site) }
        configuration.defaultRuntimeID = nil
        site.phpSelection = .followDefault
        #expect(throws: (any Error).self) { try configuration.runtime(for: site) }
    }

    @Test func inspectionUsesActualOutputs() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = InspectionRunner()
        let provider = DevelopmentRuntimeProvider(runner: runner)
        let runtime = try await provider.inspectPHP(cli: URL(fileURLWithPath: "/local/php"),
                                                   fpm: URL(fileURLWithPath: "/local/php-fpm"), workDirectory: root)
        #expect(runtime.version == "8.4.0")
        #expect(runtime.fpmExtensions == ["Core", "json"])
        let requests = await runner.requests
        #expect(requests.filter { $0.executable.lastPathComponent != "lipo" }.allSatisfy { $0.arguments.first == "-n" })
        await #expect(throws: (any Error).self) {
            try await DevelopmentRuntimeProvider(runner: InspectionRunner(mismatch: true))
                .inspectPHP(cli: URL(fileURLWithPath: "/local/php"), fpm: URL(fileURLWithPath: "/local/php-fpm"), workDirectory: root)
        }
    }
}

actor InspectionRunner: CommandRunning {
    var requests: [ProcessRequest] = []
    let mismatch: Bool
    init(mismatch: Bool = false) { self.mismatch = mismatch }
    func run(_ request: ProcessRequest, timeout: Duration) -> CommandResult {
        requests.append(request)
        let output: String
        if request.executable.lastPathComponent == "lipo" { output = CPUArchitecture.current.rawValue }
        else if request.arguments.contains("-r") { output = "{\"version\":\"8.4.0\",\"sapi\":\"cli\",\"extensions\":[\"Core\",\"json\"]}" }
        else if request.arguments.contains("-v") { output = "PHP \(mismatch ? "8.3.0" : "8.4.0") (fpm-fcgi)" }
        else if request.arguments.contains("-m") { output = "[PHP Modules]\nCore\njson\n\n[Zend Modules]\n" }
        else if request.arguments == ["version"] { output = "v2.9.0" }
        else { output = "" }
        return CommandResult(status: 0, output: output)
    }
}

struct ConfigurationTests {
    @Test func deterministicAndRestricted() throws {
        let paths = EnginePaths(root: URL(fileURLWithPath: "/tmp/run café"), socketDirectory: URL(fileURLWithPath: "/tmp/jerd-test"))
        let site = makeSite(URL(fileURLWithPath: "/tmp/project space 项目"))
        let first = try ConfigurationGenerator.caddy(site: site, paths: paths, httpsPort: 18443, httpPort: 18080)
        #expect(first == (try ConfigurationGenerator.caddy(site: site, paths: paths, httpsPort: 18443, httpPort: 18080)))
        let config = try #require(JSONSerialization.jsonObject(with: first) as? [String: Any])
        let admin = try #require(config["admin"] as? [String: Any])
        #expect(admin["disabled"] as? Bool == true)
        let apps = try #require(config["apps"] as? [String: Any])
        let http = try #require(apps["http"] as? [String: Any])
        let servers = try #require(http["servers"] as? [String: [String: Any]])
        #expect(servers["https"]?["listen"] as? [String] == ["127.0.0.1:18443"])
        #expect(servers["http"]?["listen"] as? [String] == ["127.0.0.1:18080"])
        let text = String(decoding: first, as: UTF8.self)
        #expect(text.contains("\"install_trust\" : false"))
        #expect(text.contains("\"internal\""))
        #expect(!text.contains("acme"))
        #expect(text.contains("421"))
        #expect(text.contains("fastcgi"))
        #expect(text.contains(".env"))
        #expect(text.contains(".git"))
        #expect(text.contains("php[0-9]*|phtml|phar|inc)(/|$)"))
        let routes = try #require(servers["https"]?["routes"] as? [[String: Any]])
        let handlers = try #require(routes[0]["handle"] as? [[String: Any]])
        let applicationRoutes = try #require(handlers[0]["routes"] as? [[String: Any]])
        let firstMatcher = try #require(applicationRoutes[2]["match"] as? [[String: Any]])
        let regexp = try #require(firstMatcher[0]["path_regexp"] as? [String: String])
        let pattern = try NSRegularExpression(pattern: #require(regexp["pattern"]))
        for path in ["/.env", "/.git/config", "/index.php.bak", "/private.PHP.txt", "/file.phar",
                     "/packages/foo/auth.json"] {
            #expect(pattern.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil)
        }
        for path in ["/index.php", "/index.php/route", "/js/app.include.js", "/hello.txt"] {
            #expect(pattern.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) == nil)
        }
        let fpm = try ConfigurationGenerator.fpm(paths: paths)
        #expect(fpm.contains("listen.mode = 0600"))
        #expect(fpm.contains("daemonize = no"))
        #expect(fpm.contains("pm.max_children = 8"))
        #expect(!fpm.contains("user = root"))
        #expect(fpm == (try ConfigurationGenerator.fpm(paths: paths)))
        #expect(throws: (any Error).self) { try ConfigurationGenerator.caddy(site: site, paths: paths, httpsPort: 443, httpPort: 80) }
    }
}

struct ProcessTests {
    @Test func groupCleanupAfterLeaderExit() async throws {
        let root = try temporaryDirectory(" process café")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("process-tree.c")
        let executable = root.appendingPathComponent("process-tree")
        let compile = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/clang"),
            arguments: [source.path, "-o", executable.path], directory: root), timeout: .seconds(30))
        #expect(compile.status == 0, "\(compile.output)")
        let supervisor = ProcessSupervisor()
        let log = root.appendingPathComponent("tree.log")
        let id = try await supervisor.start(ProcessRequest(executable: executable, arguments: [], directory: root), log: log)
        let deadline = ContinuousClock.now + .seconds(3)
        while await supervisor.isRunning(id), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
        let output = try String(contentsOf: log, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let childPID = try #require(Int32(output))
        #expect(kill(childPID, 0) == 0)
        await supervisor.stopAll()
        let cleanupDeadline = ContinuousClock.now + .seconds(3)
        while kill(childPID, 0) == 0, ContinuousClock.now < cleanupDeadline { try await Task.sleep(for: .milliseconds(25)) }
        #expect(kill(childPID, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test func occupiedPortIsPreserved() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                guard Darwin.bind(descriptor, raw, length) == 0 else { return Int32(-1) }
                return getsockname(descriptor, raw, &length)
            }
        }
        #expect(result == 0)
        #expect(throws: (any Error).self) { try LoopbackPort.checkAvailable(UInt16(bigEndian: address.sin_port)) }
        #expect(listen(descriptor, 1) == 0)
    }

    @Test func launchFailureAndOwnedCleanup() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let supervisor = ProcessSupervisor()
        await #expect(throws: (any Error).self) {
            try await supervisor.start(ProcessRequest(executable: URL(fileURLWithPath: "/missing/jerd-binary"),
                                                       arguments: [], directory: root), log: root.appendingPathComponent("missing.log"))
        }
        let id = try await supervisor.start(ProcessRequest(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], directory: root),
                                            log: root.appendingPathComponent("sleep.log"))
        #expect(await supervisor.isRunning(id))
        await supervisor.stopAll()
        #expect(await !supervisor.isRunning(id))
        await supervisor.stopAll()
    }

    @Test func commandFailureAndTimeout() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = LocalCommandRunner()
        let failure = try await runner.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], directory: root), timeout: .seconds(2))
        #expect(failure.status != 0)
        await #expect(throws: (any Error).self) {
            try await runner.run(ProcessRequest(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], directory: root), timeout: .milliseconds(50))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func engineCleansFPMWhenCaddyFails() async throws {
        let root = try temporaryDirectory()
        let socketDirectory = URL(fileURLWithPath: "/tmp/jerd-unit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: socketDirectory) }
        let paths = EnginePaths(root: root.appendingPathComponent("run"), socketDirectory: socketDirectory)
        let processes = FailingCaddyProcesses(socket: paths.socket)
        let engine = ServingEngine(processes: processes, commands: InspectionRunner())
        let httpsPort = try freePort()
        var httpPort = try freePort()
        while httpPort == httpsPort { httpPort = try freePort() }
        await #expect(throws: (any Error).self) {
            try await engine.start(site: makeSite(root), runtime: sampleRuntime(),
                                   caddy: CaddyRuntime(path: "/local/caddy", version: "v2.9.0", architectures: [.current]),
                                   paths: paths, httpsPort: httpsPort, httpPort: httpPort)
        }
        #expect(await processes.startCount == 2)
        #expect(await processes.stopped)
        #expect(!FileManager.default.fileExists(atPath: socketDirectory.path))
        if case .failed = await engine.state {} else { Issue.record("Expected a failed engine state") }
    }

    @Test func unknownSocketDirectoryIsPreserved() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("existing-sockets")
        try PrivateFiles.directory(existing)
        let marker = existing.appendingPathComponent("keep")
        try Data("owned elsewhere".utf8).write(to: marker)
        let paths = EnginePaths(root: root.appendingPathComponent("run"), socketDirectory: existing)
        let processes = FailingCaddyProcesses(socket: paths.socket)
        let engine = ServingEngine(processes: processes, commands: InspectionRunner())
        let httpsPort = try freePort()
        var httpPort = try freePort()
        while httpPort == httpsPort { httpPort = try freePort() }
        await #expect(throws: (any Error).self) {
            try await engine.start(site: makeSite(root), runtime: sampleRuntime(),
                                   caddy: CaddyRuntime(path: "/local/caddy", version: "v2.9.0", architectures: [.current]),
                                   paths: paths, httpsPort: httpsPort, httpPort: httpPort)
        }
        await engine.stop()
        #expect(await processes.startCount == 0)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "owned elsewhere")
    }
}

actor FailingCaddyProcesses: ProcessControlling {
    let socketURL: URL
    var descriptor: Int32 = -1
    var startCount = 0
    var stopped = false
    init(socket: URL) { socketURL = socket }
    func start(_ request: ProcessRequest, log: URL) throws -> UUID {
        startCount += 1
        if startCount == 2 { throw JerdError.process("Injected Caddy launch failure") }
        descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            socketURL.path.withCString { source in
                pointer.withMemoryRebound(to: CChar.self, capacity: 104) { strlcpy($0, source, 104) }
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { throw JerdError.process("Cannot create unit test socket") }
        return UUID()
    }
    func isRunning(_ id: UUID) -> Bool { !stopped }
    func processIdentifier(_ id: UUID) -> Int32? { nil }
    func stop(_ id: UUID, gracefulSignal: Int32) { stopAll() }
    func stopAll() {
        stopped = true
        if descriptor >= 0 { close(descriptor); descriptor = -1 }
    }
}
