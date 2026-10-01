import Foundation
import Testing
import Darwin
@testable import JerdCore

private func freeDatabasePort() throws -> UInt16 {
    let sockets = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
    defer { sockets.close() }
    return try sockets.ports().http
}

struct DatabaseTests {
    @Test func storedVersionsCannotBeReassignedAndRemovalKeepsData() async throws {
        let root = try temporaryDirectory(" databases café")
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = DatabaseManager(directory: root)
        _ = try await manager.load()
        let first = DatabaseRuntime(id: "redis-1", engine: .redis, version: "1.0", path: root.path)
        let second = DatabaseRuntime(id: "redis-2", engine: .redis, version: "2.0", path: root.path)
        try await manager.registerRuntimes([first, second])
        let service = try await manager.add(name: "Cache", runtimeID: first.id, port: freeDatabasePort())
        let paths = DatabasePaths(directory: root, serviceID: service.id)
        try PrivateFiles.directory(paths.data)
        let data = Data("Retain this database.".utf8)
        let stored = paths.data.appendingPathComponent("user-data")
        try data.write(to: stored)
        var next = await manager.snapshot().configuration
        next.services[0] = DatabaseService(id: service.id, name: service.name, runtimeID: second.id, port: service.port)
        let store = DatabaseStore(directory: root)
        await #expect(throws: (any Error).self) { try await store.save(next) }
        #expect(try await store.load().services.first?.runtimeID == first.id)
        try await manager.remove(service.id)
        #expect(try Data(contentsOf: stored) == data)
        #expect(try await store.load().services.isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("services.previous.json").path))
    }

    @Test(arguments: [Data(), Data("{\"schemaVersion\":99,\"runtimes\":[],\"services\":[]}".utf8)])
    func corruptDatabaseSettingsAreNeverReplaced(_ original: Data) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("services.json")
        try original.write(to: file)
        let store = DatabaseStore(directory: root)
        await #expect(throws: (any Error).self) { try await store.load() }
        await #expect(throws: (any Error).self) { try await store.save(DatabaseConfiguration()) }
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func invalidPortsAndDuplicatePortsAreRejected() throws {
        var configuration = DatabaseConfiguration()
        let runtime = DatabaseRuntime(id: "mysql-8.4", engine: .mysql, version: "8.4.11", path: "/example/runtime")
        configuration.runtimes = [runtime]
        configuration.services = [DatabaseService(name: "First", runtimeID: runtime.id, port: 3307)]
        try configuration.validate()
        configuration.services.append(DatabaseService(name: "Second", runtimeID: runtime.id, port: 3307))
        #expect(throws: (any Error).self) { try configuration.validate() }
        configuration.services.removeLast()
        configuration.services[0].port = 443
        #expect(throws: (any Error).self) { try configuration.validate() }
    }

    @Test func occupiedPortDoesNotStartOrStopAnyDatabase() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = DatabaseManager(directory: root)
        _ = try await manager.load()
        let runtime = DatabaseRuntime(id: "redis-test", engine: .redis, version: "8.8.3", path: "/missing-runtime")
        try await manager.registerRuntimes([runtime])
        let service = try await manager.add(name: "Test", runtimeID: runtime.id, port: freeDatabasePort())
        let occupied = try ListeningSockets.bind(httpPort: service.port, httpsPort: 0)
        defer { occupied.close() }
        await #expect(throws: (any Error).self) { try await manager.start(service.id) }
        let snapshot = await manager.snapshot()
        guard case .failed(let reason) = snapshot.statuses[service.id]?.state else { Issue.record("Expected a port failure"); return }
        #expect(reason.contains("occupied"))
        #expect(snapshot.statuses[service.id]?.processID == nil)
        #expect(try occupied.ports().http == service.port)
        #expect(!FileManager.default.fileExists(atPath: DatabasePaths(directory: root, serviceID: service.id).root.path))
    }

    @Test func aClosedConnectionDoesNotBlockServerRestart() throws {
        let sockets = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
        defer { sockets.close() }
        let port = try sockets.ports().http
        let client = socket(AF_INET, SOCK_STREAM, 0)
        guard client >= 0 else { throw JerdError.process("Cannot create test client") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { close(client); throw JerdError.process("Cannot connect test client") }
        let accepted = accept(sockets.http.fileDescriptor, nil, nil)
        guard accepted >= 0 else { close(client); throw JerdError.process("Cannot accept test client") }
        // The server closes first, leaving its port in TCP TIME_WAIT.
        close(accepted)
        var byte: UInt8 = 0
        #expect(recv(client, &byte, 1, 0) == 0)
        close(client)
        sockets.close()
        try LoopbackPort.checkAvailable(port)
    }

    @Test(arguments: DatabaseEngine.allCases)
    func passwordsStayOutOfArgumentsAndFilesArePrivate(_ engine: DatabaseEngine) throws {
        let root = try temporaryDirectory(" credentials café")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DatabaseService(name: "Local", runtimeID: "test", port: 19999)
        let runtime = DatabaseRuntime(id: "test", engine: engine, version: "1.0", path: root.path)
        let paths = DatabasePaths(directory: root, serviceID: service.id)
        try PrivateFiles.directory(paths.root)
        let credentials = try DatabaseCredentials()
        try DatabaseDriver.writeConfiguration(runtime: runtime, service: service, paths: paths, credentials: credentials, sockets: root)
        let server = DatabaseDriver.server(runtime: runtime, service: service, paths: paths, sockets: root)
        let client = DatabaseDriver.healthCheck(runtime: runtime, service: service, paths: paths, credentials: credentials)
        #expect(!(server.arguments + client.arguments).joined().contains(credentials.password))
        let file = engine == .mysql ? paths.clientOptions : (engine == .postgresql ? paths.pgpass : paths.redisConfig)
        let mode = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
        #expect(mode.intValue & 0o777 == 0o600)
    }

    @Test func gracefulTimeoutKeepsTheOwnedProcessForRetry() async throws {
        let root = try temporaryDirectory(" graceful database")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("graceful-process.c")
        let binary = root.appendingPathComponent("graceful-process")
        let result = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/clang"),
            arguments: [source.path, "-o", binary.path], directory: root), timeout: .seconds(20))
        #expect(result.status == 0)
        let supervisor = ProcessSupervisor()
        let log = root.appendingPathComponent("process.log")
        do {
            let token = try await supervisor.start(ProcessRequest(executable: binary, arguments: [], directory: root), log: log)
            let pid = await supervisor.processIdentifier(token)
            let deadline = ContinuousClock.now + .seconds(2)
            while (try? String(contentsOf: log, encoding: .utf8).contains("ready")) != true, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(try String(contentsOf: log, encoding: .utf8).contains("ready"))
            #expect(!(await supervisor.stopGracefully(token, timeout: .milliseconds(80))))
            #expect(await supervisor.isRunning(token))
            #expect(await supervisor.processIdentifier(token) == pid)
            #expect(await supervisor.stopGracefully(token, signal: SIGINT, timeout: .seconds(2)))
            #expect(!(await supervisor.isRunning(token)))
        } catch { await supervisor.stopAll(); throw error }
        await supervisor.stopAll()
    }
}

struct DatabaseIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_OCCUPIED_DATABASE_PORT"] != nil,
                   "Read-only regression check against an existing wildcard listener."))
    func existingWildcardListenerPreventsRegistration() async throws {
        let selectedPort = try #require(ProcessInfo.processInfo.environment["JERD_OCCUPIED_DATABASE_PORT"])
        let port = try #require(UInt16(selectedPort))
        let root = try temporaryDirectory(" occupied wildcard database")
        defer { try? FileManager.default.removeItem(at: root) }
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpn"], directory: root)
        let before = try await LocalCommandRunner().run(request, timeout: .seconds(5))
        #expect(before.status == 0 && before.output.contains("n*:\(port)"))
        let manager = DatabaseManager(directory: root)
        _ = try await manager.load()
        try await manager.registerRuntimes([DatabaseRuntime(id: "redis-test", engine: .redis, version: "8.8.3", path: "/missing-runtime")])
        await #expect(throws: (any Error).self) { try await manager.add(name: "Test", runtimeID: "redis-test", port: port) }
        #expect(await manager.snapshot().configuration.services.isEmpty)
        if port == DatabaseEngine.redis.defaultPort {
            #expect(try await manager.suggestedPort(for: .redis) != port)
        }
        let after = try await LocalCommandRunner().run(request, timeout: .seconds(5))
        #expect(after.status == before.status && after.output == before.output)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_DATABASE_INTEGRATION"] == "1",
                   "Select independently prepared native database runtimes for this test."))
    func threeEnginesAuthenticatePersistAndStopIndependently() async throws {
        struct Pins: Decodable {
            struct Artifact: Decodable { let id: String; let engine: DatabaseEngine; let version: String }
            let artifacts: [Artifact]
        }
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["JERD_DATABASE_RUNTIMES"]))
        let pins = try JSONDecoder().decode(Pins.self, from: Data(contentsOf: source.appendingPathComponent("pins.json")))
        let root = try temporaryDirectory(" database persistence café")
        let manager = DatabaseManager(directory: root)
        _ = try await manager.load()
        let runtimes = pins.artifacts.map { DatabaseRuntime(id: $0.id, engine: $0.engine, version: $0.version, path: source.appendingPathComponent($0.id).path) }
        try await manager.registerRuntimes(runtimes)
        var services: [DatabaseService] = []
        for runtime in runtimes {
            services.append(try await manager.add(name: runtime.engine.title, runtimeID: runtime.id, port: freeDatabasePort()))
        }
        func request(_ service: DatabaseService, _ command: [String]) async throws -> CommandResult {
            guard let runtime = runtimes.first(where: { $0.id == service.runtimeID }) else { throw JerdError.invalid("Missing test runtime") }
            let paths = DatabasePaths(directory: root, serviceID: service.id)
            let credentials = try JSONDecoder().decode(DatabaseCredentials.self, from: Data(contentsOf: paths.credentials))
            return try await LocalCommandRunner().run(DatabaseDriver.client(runtime: runtime, service: service, paths: paths,
                credentials: credentials, command: command), timeout: .seconds(5))
        }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for service in services { group.addTask { try await manager.start(service.id) } }
                try await group.waitForAll()
            }
            let initial = await manager.snapshot()
            #expect(initial.statuses.values.filter { $0.state == .running }.count == 3)
            for service in services {
                let runtime = try #require(runtimes.first { $0.id == service.runtimeID })
                let command = runtime.engine == .redis ? ["SET", "jerd-persistence", "42"] : ["CREATE TABLE jerd_persistence (value INTEGER)", "INSERT INTO jerd_persistence VALUES (42)"]
                let written = try await request(service, command)
                #expect(written.status == 0, "\(runtime.engine.title): \(written.output)")
                let paths = DatabasePaths(directory: root, serviceID: service.id)
                let credentials = try JSONDecoder().decode(DatabaseCredentials.self, from: Data(contentsOf: paths.credentials))
                let wrong = try DatabaseCredentials()
                try DatabaseDriver.writeConfiguration(runtime: runtime, service: service, paths: paths, credentials: wrong, sockets: root)
                defer { try? DatabaseDriver.writeConfiguration(runtime: runtime, service: service, paths: paths, credentials: credentials, sockets: root) }
                let denied = try await LocalCommandRunner().run(DatabaseDriver.healthCheck(runtime: runtime, service: service, paths: paths,
                    credentials: wrong), timeout: .seconds(4))
                #expect(denied.status != 0 || !["42", "PONG"].contains(denied.output.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            let postgres = try #require(services.first { $0.runtimeID.hasPrefix("postgresql-") })
            try await manager.stop(postgres.id)
            let partial = await manager.snapshot()
            #expect(partial.statuses[postgres.id]?.state == .stopped)
            #expect(partial.statuses.values.filter { $0.state == .running }.count == 2)
            try await manager.start(postgres.id)
            #expect(try await request(postgres, ["SELECT value FROM jerd_persistence"]).output.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
            try await manager.stopAll()
            let pgPaths = DatabasePaths(directory: root, serviceID: postgres.id)
            let identity = try Data(contentsOf: pgPaths.identity)
            var changed = try #require(JSONSerialization.jsonObject(with: identity) as? [String: Any])
            changed["version"] = "17.0"
            try JSONSerialization.data(withJSONObject: changed).write(to: pgPaths.identity)
            await #expect(throws: (any Error).self) { try await manager.start(postgres.id) }
            #expect(try String(contentsOf: pgPaths.data.appendingPathComponent("PG_VERSION"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "18")
            try identity.write(to: pgPaths.identity)
            for service in services { try await manager.start(service.id) }
            for service in services {
                let runtime = try #require(runtimes.first { $0.id == service.runtimeID })
                let read = try await request(service, runtime.engine == .redis ? ["GET", "jerd-persistence"] : ["SELECT value FROM jerd_persistence"])
                #expect(read.status == 0)
                #expect(read.output.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
            }
            let redis = try #require(services.first { $0.runtimeID.hasPrefix("redis-") })
            _ = try await request(redis, ["SHUTDOWN"])
            let deadline = ContinuousClock.now + .seconds(3)
            while await manager.snapshot().statuses[redis.id]?.state == .running, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            let exited = await manager.snapshot()
            guard case .failed = exited.statuses[redis.id]?.state else { throw JerdError.invalid("Expected Redis exit detection") }
            #expect(exited.statuses.values.filter { $0.state == .running }.count == 2)
            try await manager.start(redis.id)
            let credentialsBefore = try Data(contentsOf: pgPaths.credentials)
            try await manager.remove(postgres.id)
            #expect(FileManager.default.fileExists(atPath: pgPaths.data.appendingPathComponent("PG_VERSION").path))
            #expect(try Data(contentsOf: pgPaths.credentials) == credentialsBefore)
            #expect(await manager.snapshot().statuses.values.filter { $0.state == .running }.count == 2)
            try await manager.stopAll()
            let reloaded = DatabaseManager(directory: root)
            let configuration = try await reloaded.load()
            #expect(configuration.services.count == 2)
            #expect(!configuration.services.contains { $0.id == postgres.id })
            try FileManager.default.removeItem(at: root)
        } catch {
            do { try await manager.stopAll(); try FileManager.default.removeItem(at: root) }
            catch { Issue.record("Database test data was retained because cleanup could not complete.") }
            throw error
        }
    }
}
