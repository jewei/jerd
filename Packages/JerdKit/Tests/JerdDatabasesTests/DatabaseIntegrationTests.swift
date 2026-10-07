import Darwin
import Foundation
import JerdDatabases
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import JerdTestSupport
import Testing

/// Opt-in tests with real MySQL, PostgreSQL, and Redis runtimes. They use temporary instances and
/// free loopback ports only, and never touch existing databases.
@Suite(.serialized) struct DatabaseIntegrationTests {
    static let environment = ProcessInfo.processInfo.environment

    @Test(
        .enabled(if: environment["JERD_DATABASE_INTEGRATION"] == "1" && environment["JERD_DATABASE_RUNTIMES"] != nil))
    func threeEnginesAuthenticatePersistAndStopIndependently() async throws {
        let source = URL(fileURLWithPath: try #require(Self.environment["JERD_DATABASE_RUNTIMES"]))
        let run = try await IntegrationRun(runtimes: source)
        var services: [DatabaseService] = []
        for runtime in run.runtimes {
            services.append(
                try await run.manager.add(
                    name: runtime.engine.title, runtimeID: runtime.id, port: IntegrationRun.freePort()))
        }
        do {
            try await startInParallel(run, services)
            try await writeAndRejectWrongPasswords(run, services)
            try await stopOneAndRefuseAnotherVersion(run, services)
            try await detectAnExternalShutdown(run, services)
            try await removeAndRestoreKeepData(run, services)
            try await run.manager.stopAll()
            let reloaded = DatabaseManager(layout: run.layout, effects: ServiceEffects(processes: ProcessSupervisor()))
            #expect(try await reloaded.load().services.count == 3)
            run.directory.remove()
        } catch {
            do {
                try await run.manager.stopAll()
                run.directory.remove()
            } catch {
                Issue.record("Database test data was kept in \(run.directory.url.path) because cleanup failed.")
            }
            throw error
        }
    }

    private func service(_ services: [DatabaseService], _ engine: DatabaseEngine) throws -> DatabaseService {
        try #require(services.first { $0.runtimeID.hasPrefix(engine.rawValue) })
    }

    private func startInParallel(_ run: IntegrationRun, _ services: [DatabaseService]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for service in services { group.addTask { try await run.manager.start(service.id) } }
            try await group.waitForAll()
        }
        let states = await run.manager.snapshot().states.values
        #expect(states.filter { $0.processID != nil && !$0.isBusy }.count == 3)
    }

    private func writeAndRejectWrongPasswords(_ run: IntegrationRun, _ services: [DatabaseService]) async throws {
        for service in services {
            let engine = try run.engine(of: service)
            let command =
                engine.runtime.engine == .redis
                ? ["SET", "jerd-persistence", "42"]
                : ["CREATE TABLE jerd_persistence (value INTEGER)", "INSERT INTO jerd_persistence VALUES (42)"]
            _ = try await run.value(service, command)
            let saved = try run.credentials(of: service)
            let wrong = try DatabaseCredentials.generate()
            let sockets = FileManager.default.temporaryDirectory
            try engine.configuration(wrong, sockets: sockets).write()
            let denied = try await CommandRunner().run(
                engine.clientRequest(engine.healthCheck.command, credentials: wrong), timeout: .seconds(4))
            try engine.configuration(saved, sockets: sockets).write()
            let reply = denied.output.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!denied.succeeded || reply != engine.healthCheck.reply, "\(service.name) accepted a wrong password")
        }
    }

    private func stopOneAndRefuseAnotherVersion(_ run: IntegrationRun, _ services: [DatabaseService]) async throws {
        let postgres = try service(services, .postgresql)
        try await run.manager.stop(postgres.id)
        #expect(await run.manager.snapshot().state(of: postgres.id) == .stopped)
        #expect(await run.manager.snapshot().states.values.filter { $0.processID != nil }.count == 2)
        try await run.manager.start(postgres.id)
        #expect(try await run.value(postgres, ["SELECT value FROM jerd_persistence"]) == "42")
        try await run.manager.stop(postgres.id)
        let identity = run.layout.instance(postgres.id).runtimeIdentityFile
        let original = try #require(contents(identity))
        var changed = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        changed["version"] = "17.0"
        try AtomicFile.write(JSONSerialization.data(withJSONObject: changed), to: identity)
        await #expect(throws: (any Error).self) { try await run.manager.start(postgres.id) }
        let pgVersion = run.layout.instance(postgres.id).dataDirectory.appendingPathComponent("PG_VERSION")
        #expect(text(pgVersion).trimmingCharacters(in: .whitespacesAndNewlines) == "18")
        try AtomicFile.write(original, to: identity)
        try await run.manager.start(postgres.id)
    }

    private func detectAnExternalShutdown(_ run: IntegrationRun, _ services: [DatabaseService]) async throws {
        let redis = try service(services, .redis)
        _ = try await run.query(redis, ["SHUTDOWN"])
        let failed = await eventually(timeout: .seconds(10)) {
            if case .failed = await run.manager.snapshot().state(of: redis.id) { return true }
            return false
        }
        #expect(failed, "Expected Redis exit detection")
        #expect(await run.manager.snapshot().states.values.filter { $0.processID != nil }.count == 2)
        try await run.manager.start(redis.id)
        #expect(try await run.value(redis, ["GET", "jerd-persistence"]) == "42")
    }

    private func removeAndRestoreKeepData(_ run: IntegrationRun, _ services: [DatabaseService]) async throws {
        let postgres = try service(services, .postgresql)
        let credentials = contents(run.layout.instance(postgres.id).credentialsFile)
        try await run.manager.remove(postgres.id)
        let retained = try await run.manager.retainedDatabases()
        #expect(retained.count == 1 && retained.first?.id == postgres.id && retained.first?.canRestore == true)
        let restored = try await run.manager.restoreRegistration(postgres.id, name: "Restored", port: postgres.port)
        try await run.manager.start(restored.id)
        #expect(try await run.value(restored, ["SELECT value FROM jerd_persistence"]) == "42")
        #expect(contents(run.layout.instance(postgres.id).credentialsFile) == credentials)
    }

    @Test(.enabled(if: environment["JERD_OCCUPIED_DATABASE_PORT"] != nil))
    func anExistingWildcardListenerPreventsRegistration() async throws {
        let selected = try #require(Self.environment["JERD_OCCUPIED_DATABASE_PORT"])
        let port = try #require(UInt16(selected))
        let directory = try TemporaryDirectory(" occupied database port")
        defer { directory.remove() }
        let lsof = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpn"],
            workingDirectory: directory.url)
        let before = try await CommandRunner().run(lsof, timeout: .seconds(5))
        let manager = DatabaseManager(
            layout: DataLayout(root: directory.path("Jerd")).databases,
            effects: ServiceEffects(processes: ProcessSupervisor()))
        _ = try await manager.load()
        let runtime = DatabaseRuntime(id: "redis-test", engine: .redis, version: "8.8.3", path: "/missing-runtime")
        try await manager.registerRuntimes([runtime])
        await #expect(throws: (any Error).self) {
            _ = try await manager.add(name: "Test", runtimeID: runtime.id, port: port)
        }
        #expect(await manager.snapshot().configuration.services.isEmpty)
        if port == DatabaseEngine.redis.defaultPort { #expect(try await manager.suggestedPort(for: .redis) != port) }
        let after = try await CommandRunner().run(lsof, timeout: .seconds(5))
        #expect(after.status == before.status && after.output == before.output)
    }
}
