import Foundation
import Testing
import Darwin
@testable import JerdCore

struct TLSSmokeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_INTEGRATION"] == "1",
                   "Select independent PHP and Caddy binaries for the public storage test."))
    func publicStorageAssetsDoNotExposePrivateStorageOrExecutePHP() async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = try temporaryDirectory(" public storage")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("laravel")
        let publicRoot = project.appendingPathComponent("public")
        let publicStorage = project.appendingPathComponent("storage/app/public")
        let privateProject = root.appendingPathComponent("project-root")
        try PrivateFiles.directory(publicRoot)
        try PrivateFiles.directory(publicStorage.appendingPathComponent("112"))
        try PrivateFiles.directory(publicStorage.appendingPathComponent("directory"))
        try PrivateFiles.directory(privateProject.appendingPathComponent("storage/logs"))
        try Data("<?php echo 'front-controller';".utf8).write(to: publicRoot.appendingPathComponent("index.php"))
        try Data("<?php echo 'other-site';".utf8).write(to: privateProject.appendingPathComponent("index.php"))
        try Data("private-log-must-not-leak".utf8).write(to: privateProject.appendingPathComponent("storage/logs/laravel.log"))
        try Data("private-env-must-not-leak".utf8).write(to: publicStorage.appendingPathComponent(".env"))
        let asset = Data([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x4a, 0x46, 0xff, 0xd9])
        try asset.write(to: publicStorage.appendingPathComponent("112/amazon-us.jpg"))
        let scripts = ["upload.php", "upload.PHP", "upload.php.bak", "upload.phtml", "upload.phar"]
        for name in scripts {
            try Data("<?php echo 'upload-must-not-execute';".utf8).write(to: publicStorage.appendingPathComponent(name))
        }
        try Data("<?php echo 'directory-index-must-not-execute';".utf8)
            .write(to: publicStorage.appendingPathComponent("directory/index.php"))
        try FileManager.default.createSymbolicLink(at: publicRoot.appendingPathComponent("storage"),
                                                   withDestinationURL: publicStorage)
        var publicSite = makeSite(project, hostname: "public-storage.test")
        publicSite.documentRoot = publicRoot.path
        let privateSite = makeSite(privateProject, hostname: "private-storage.test")
        let paths = EnginePaths(root: root.appendingPathComponent("engine"),
            socketDirectory: URL(fileURLWithPath: "/tmp/jerd-storage-\(UUID().uuidString.prefix(12))"))
        let provider = DevelopmentRuntimeProvider()
        let runtime = try await provider.inspectPHP(cli: URL(fileURLWithPath: try #require(environment["JERD_PHP_CLI"])),
            fpm: URL(fileURLWithPath: try #require(environment["JERD_PHP_FPM"])), workDirectory: root)
        let caddy = try await provider.inspectCaddy(binary: URL(fileURLWithPath: try #require(environment["JERD_CADDY"])), workDirectory: root)
        let sockets = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
        defer { sockets.close() }
        let ports = try sockets.ports()
        let engine = ServingEngine()
        do {
            try await engine.start(sites: [SiteRuntime(site: publicSite, runtime: runtime), SiteRuntime(site: privateSite, runtime: runtime)],
                caddy: caddy, paths: paths, httpsPort: ports.https, httpPort: ports.http, listeningSockets: sockets)
            func request(_ host: String, _ path: String) async throws -> (String, Data) {
                let output = root.appendingPathComponent("response-\(UUID().uuidString)")
                let result = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                    arguments: ["--noproxy", "*", "--silent", "--show-error", "--max-time", "4",
                        "--cacert", paths.rootCertificate.path, "--resolve", "\(host):\(ports.https):127.0.0.1",
                        "--output", output.path, "--write-out", "%{http_code} %{content_type}",
                        "https://\(host):\(ports.https)\(path)"], directory: root), timeout: .seconds(6))
                #expect(result.status == 0)
                return (result.output, try Data(contentsOf: output))
            }
            let image = try await request(publicSite.hostname, "/storage/112/amazon-us.jpg")
            #expect(image.0 == "200 image/jpeg")
            #expect(image.1 == asset)
            #expect(try await request(publicSite.hostname, "/").1 == Data("front-controller".utf8))
            for path in ["/storage/.env", "/storage/upload.php/extra", "/storage/directory", "/storage/directory/"] + scripts.map({ "/storage/\($0)" }) {
                let denied = try await request(publicSite.hostname, path)
                #expect(denied.0.hasPrefix("404 "), "Unexpected response for \(path): \(denied.0)")
                #expect(denied.1.isEmpty)
            }
            let privateStorage = try await request(privateSite.hostname, "/storage/logs/laravel.log")
            #expect(privateStorage.0.hasPrefix("404 "))
            #expect(privateStorage.1.isEmpty)
            await engine.stop()
        } catch { await engine.stop(); throw error }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_INTEGRATION"] == "1",
                   "Select the independent development runtimes for the real multi-site test."), arguments: [false, true])
    func multipleSitesUseTheirOwnRootsAndSelectedPools(separatePools: Bool) async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = try temporaryDirectory(" multi TLS")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = EnginePaths(root: root.appendingPathComponent("engine"),
            socketDirectory: URL(fileURLWithPath: "/tmp/jerd-multi-\(UUID().uuidString.prefix(12))"))
        let provider = DevelopmentRuntimeProvider()
        let runtime = try await provider.inspectPHP(cli: URL(fileURLWithPath: try #require(environment["JERD_PHP_CLI"])),
            fpm: URL(fileURLWithPath: try #require(environment["JERD_PHP_FPM"])), workDirectory: root)
        let caddy = try await provider.inspectCaddy(binary: URL(fileURLWithPath: try #require(environment["JERD_CADDY"])), workDirectory: root)
        var secondRuntime = runtime
        if separatePools { secondRuntime.id = UUID() }
        var sites: [Site] = []
        for name in ["first", "second"] {
            let folder = root.appendingPathComponent(name)
            try PrivateFiles.directory(folder)
            try Data("<?php echo '\(name)-php-' . (6 * 7);".utf8).write(to: folder.appendingPathComponent("index.php"))
            try Data("\(name)-static".utf8).write(to: folder.appendingPathComponent("hello.txt"))
            sites.append(makeSite(folder, hostname: "\(name).test"))
        }
        let sockets = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
        defer { sockets.close() }
        let ports = try sockets.ports()
        let processes = SmokeProcesses()
        let engine = ServingEngine(processes: processes)
        do {
            try await engine.start(sites: [SiteRuntime(site: sites[0], runtime: runtime), SiteRuntime(site: sites[1], runtime: secondRuntime)],
                caddy: caddy, paths: paths, httpsPort: ports.https, httpPort: ports.http, listeningSockets: sockets)
            #expect(await processes.phpProcessCount() == (separatePools ? 2 : 1))
            let testedSites = sites
            @Sendable func request(_ index: Int, _ path: String) async throws -> CommandResult {
                let host = testedSites[index].hostname
                return try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                    arguments: ["--noproxy", "*", "--silent", "--show-error", "--fail", "--max-time", "4", "--cacert", paths.rootCertificate.path,
                        "--resolve", "\(host):\(ports.https):127.0.0.1", "https://\(host):\(ports.https)\(path)"], directory: root), timeout: .seconds(6))
            }
            async let first = request(0, "/")
            async let second = request(1, "/")
            let responses = try await (first, second)
            #expect(responses.0.status == 0 && responses.0.output == "first-php-42")
            #expect(responses.1.status == 0 && responses.1.output == "second-php-42")
            #expect(try await request(0, "/hello.txt").output == "first-static")
            #expect(try await request(1, "/hello.txt").output == "second-static")
            await engine.stop()
            #expect(await processes.allStopped())
        } catch { await engine.stop(); throw error }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_INTEGRATION"] == "1",
                   "Set JERD_INTEGRATION=1 and select independent local PHP CLI/FPM and Caddy binaries."),
          arguments: [false, true])
    func actualPHPResponseOverVerifiedTLS(inherited: Bool) async throws {
        let environment = ProcessInfo.processInfo.environment
        func binary(_ name: String) throws -> URL {
            guard let path = environment[name], path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
                throw JerdError.unavailable("The opt-in test requires \(name) to name an executable at an absolute path.")
            }
            return URL(fileURLWithPath: path)
        }
        let cli = try binary("JERD_PHP_CLI")
        let fpm = try binary("JERD_PHP_FPM")
        let caddyBinary = try binary("JERD_CADDY")
        let root = try temporaryDirectory(" TLS café 项目")
        let socketDirectory = URL(fileURLWithPath: "/tmp/jerd-smoke-\(UUID().uuidString)")
        let paths = EnginePaths(root: root.appendingPathComponent("engine"), socketDirectory: socketDirectory,
                                installationID: inherited ? UUID() : nil)
        let processes = SmokeProcesses()
        let engine = ServingEngine(processes: processes)
        defer {
            if environment["JERD_KEEP_TEST_FILES"] != "1" { try? FileManager.default.removeItem(at: root) }
        }
        print("Jerd isolated TLS test files: \(root.path)")
        do {
            let fixture = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
                .appendingPathComponent("site")
            let project = root.appendingPathComponent("project café space")
            try FileManager.default.copyItem(at: fixture, to: project)
            try Data("jerd-secret".utf8).write(to: project.appendingPathComponent(".env"))
            try PrivateFiles.directory(project.appendingPathComponent(".git"))
            try Data("jerd-secret".utf8).write(to: project.appendingPathComponent(".git/config"))
            for name in ["source.PHP", "index.php.bak", "source.phtml"] {
                try Data("<?php echo 'source-must-not-leak';".utf8).write(to: project.appendingPathComponent(name))
            }
            try Data("static-ok".utf8).write(to: project.appendingPathComponent("hello.txt"))
            let provider = DevelopmentRuntimeProvider()
            let runtime = try await provider.inspectPHP(cli: cli, fpm: fpm, workDirectory: root.appendingPathComponent("inspection"))
            let caddy = try await provider.inspectCaddy(binary: caddyBinary, workDirectory: root.appendingPathComponent("inspection"))
            let site = makeSite(project, hostname: "jerd-smoke.test")
            let sockets = inherited ? try ListeningSockets.bind(httpPort: 0, httpsPort: 0) : nil
            defer { sockets?.close() }
            let httpsPort = try sockets?.ports().https ?? freePort()
            var httpPort = try sockets?.ports().http ?? freePort()
            while httpPort == httpsPort { httpPort = try freePort() }
            try await engine.start(site: site, runtime: runtime, caddy: caddy, paths: paths,
                                   httpsPort: httpsPort, httpPort: httpPort, listeningSockets: sockets)
            #expect(await engine.state == .running)
            #expect(await engine.certificate == .issued)
            #expect(await engine.trust == .setupRequired)
            if let installationID = paths.installationID {
                let der = try InstallationCertificate.decodePEM(Data(contentsOf: paths.rootCertificate))
                _ = try InstallationCertificate.validate(der, installationID: installationID)
            }

            func curl(_ path: String, extra: [String] = []) async throws -> CommandResult {
                try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                    arguments: ["--noproxy", "*", "--silent", "--show-error", "--max-time", "4",
                                "--cacert", paths.rootCertificate.path, "--resolve", "\(site.hostname):\(httpsPort):127.0.0.1"] + extra +
                                ["https://\(site.hostname):\(httpsPort)\(path)"], directory: root), timeout: .seconds(6))
            }
            let response = try await curl("/", extra: ["--fail"])
            #expect(response.status == 0)
            let body = try #require(JSONSerialization.jsonObject(with: Data(response.output.utf8)) as? [String: Any])
            #expect(body["proof"] as? String == "jerd-php-executed")
            #expect(body["sapi"] as? String == "fpm-fcgi")
            #expect(body["version"] as? String == runtime.version)
            #expect(body["answer"] as? Int == 42)
            #expect(try await curl("/hello.txt", extra: ["--fail"]).output == "static-ok")
            for path in ["/.env", "/.git/config", "/%2eenv", "/source.PHP", "/index.php.bak", "/source.phtml"] {
                let denied = try await curl(path, extra: ["--write-out", "%{http_code}"])
                #expect(denied.status == 0)
                #expect(denied.output == "404", "Unexpected response for \(path): \(denied.output)")
            }
            let unknown = try await curl("/", extra: ["--header", "Host: unknown.test", "--write-out", "%{http_code}"])
            #expect(unknown.output.hasSuffix("421"))
            let redirect = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                arguments: ["--noproxy", "*", "--silent", "--show-error", "--max-time", "4", "--dump-header", "-", "--output", "/dev/null",
                            "--header", "Host: \(site.hostname)", "http://127.0.0.1:\(httpPort)/hello.txt"], directory: root), timeout: .seconds(6))
            #expect(redirect.status == 0)
            #expect(redirect.output.contains("308"))
            #expect(redirect.output.lowercased().contains("location: https://\(site.hostname):\(httpsPort)/hello.txt"))

            // Verify failure is closed after the real FPM master is stopped.
            await processes.stopPHP()
            let unavailable = try await curl("/index.php", extra: ["--fail"])
            #expect(unavailable.status != 0)
            #expect(!unavailable.output.contains("<?php"))
            let deadline = ContinuousClock.now + .seconds(5)
            while await engine.state == .running, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
            if case .failed = await engine.state {} else { Issue.record("Unexpected FPM exit was not reported") }
            await engine.stop()
            #expect(await processes.allStopped())
            #expect(!FileManager.default.fileExists(atPath: paths.socket.path))
            print("Runtime versions: PHP \(runtime.version), Caddy \(caddy.version), \(CPUArchitecture.current.rawValue). System trust was not changed.")
        } catch {
            await engine.stop()
            await processes.stopAll()
            throw error
        }
    }
}

func freePort() throws -> UInt16 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw JerdError.process("Cannot allocate test port") }
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
    guard result == 0 else { throw JerdError.process("Cannot allocate test port") }
    return UInt16(bigEndian: address.sin_port)
}

private actor SmokeProcesses: ProcessControlling {
    private let real = ProcessSupervisor()
    private var ids: [UUID] = []
    private var phpID: UUID?
    private var phpIDs: [UUID] = []
    func start(_ request: ProcessRequest, log: URL) async throws -> UUID {
        let id = try await real.start(request, log: log)
        ids.append(id)
        if request.arguments.contains("-F") { phpID = id; phpIDs.append(id) }
        return id
    }
    func isRunning(_ id: UUID) async -> Bool { await real.isRunning(id) }
    func processIdentifier(_ id: UUID) async -> Int32? { await real.processIdentifier(id) }
    func stop(_ id: UUID, gracefulSignal: Int32) async { await real.stop(id, gracefulSignal: gracefulSignal) }
    func stopAll() async { await real.stopAll() }
    func stopPHP() async { if let phpID { await real.stop(phpID, gracefulSignal: SIGQUIT) } }
    func phpProcessCount() -> Int { phpIDs.count }
    func allStopped() async -> Bool {
        for id in ids { if await real.isRunning(id) { return false } }
        return true
    }
}
