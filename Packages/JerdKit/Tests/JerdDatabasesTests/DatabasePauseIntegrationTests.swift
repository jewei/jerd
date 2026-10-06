import Darwin
import Foundation
import JerdDatabases
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import JerdTestSupport
import Testing

/// An opt-in test with real runtimes: a paused server (`kill -STOP`, a debugger) is not an exit,
/// and Quit still stops it gracefully. It uses a temporary data folder and free loopback ports.
@Suite(.serialized) struct DatabasePauseIntegrationTests {
    static let environment = ProcessInfo.processInfo.environment

    @Test(
        .enabled(if: environment["JERD_DATABASE_INTEGRATION"] == "1" && environment["JERD_DATABASE_RUNTIMES"] != nil))
    func pausedServersKeepTheirStateAndStopGracefullyAtQuit() async throws {
        let source = URL(fileURLWithPath: try #require(Self.environment["JERD_DATABASE_RUNTIMES"]))
        let run = try await IntegrationRun(runtimes: source)
        var services: [DatabaseService] = []
        for runtime in run.runtimes {
            services.append(
                try await run.manager.add(
                    name: runtime.engine.title, runtimeID: runtime.id, port: IntegrationRun.freePort()))
        }
        var paused: [(pid: pid_t, signal: Int32)] = []
        do {
            for service in services { try await run.manager.start(service.id) }
            paused = try await pauseEveryServer(run, services)
            try await Task.sleep(for: .milliseconds(500))
            for (service, server) in zip(services, paused) {
                #expect(await run.manager.snapshot().state(of: service.id) == .running(pid: server.pid))
            }
            try await run.manager.stopAll()
            for (service, server) in zip(services, paused) {
                let instance = run.layout.instance(service.id)
                #expect(kill(server.pid, 0) == -1 && errno == ESRCH, "\(service.name) still runs")
                #expect(await run.manager.snapshot().state(of: service.id) == .stopped)
                #expect(!exists(instance.activeRunFile))
                #expect(isLockFree(instance.lockFile))
            }
        } catch {
            await endLeftovers(paused)
            do {
                try await run.manager.stopAll()
            } catch {
                Issue.record("Database test data was kept in \(run.directory.url.path) because cleanup failed.")
                throw error
            }
            run.directory.remove()
            throw error
        }
        await endLeftovers(paused)
        run.directory.remove()
    }

    /// Ends a server that Jerd lost track of. This test started it, so it may signal it by PID.
    private func endLeftovers(_ servers: [(pid: pid_t, signal: Int32)]) async {
        for server in servers where kill(server.pid, 0) == 0 {
            Issue.record("Server \(server.pid) outlived the stop.")
            kill(server.pid, server.signal)
            kill(-server.pid, SIGCONT)
            _ = await eventually(timeout: .seconds(30)) { kill(server.pid, 0) == -1 }
        }
    }

    /// Pauses the MySQL and Redis servers alone, and the whole PostgreSQL group with its backends.
    private func pauseEveryServer(
        _ run: IntegrationRun, _ services: [DatabaseService]
    ) async throws -> [(pid: pid_t, signal: Int32)] {
        var paused: [(pid: pid_t, signal: Int32)] = []
        for service in services {
            let pid = try #require(await run.manager.snapshot().state(of: service.id).processID)
            let engine = try run.runtime(of: service).engine
            paused.append((pid, engine.stopSignal))
            if engine == .postgresql {
                #expect(kill(-pid, SIGSTOP) == 0)
                #expect(await eventually { ProcessPause.isPaused(pid) })
            } else {
                #expect(await ProcessPause.pause(pid))
            }
        }
        return paused
    }
}
