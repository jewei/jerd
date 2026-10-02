import Foundation
import Darwin

public struct DatabaseSnapshot: Sendable {
    public let configuration: DatabaseConfiguration
    public let statuses: [UUID: DatabaseStatus]
}

public struct DatabaseConnection: Sendable {
    public let engine: DatabaseEngine
    public let port: UInt16
    public let password: String
    public var username: String { engine.username }
    public var database: String { engine.database }
    public var environment: String {
        if engine == .redis {
            return "REDIS_HOST=127.0.0.1\nREDIS_PORT=\(port)\nREDIS_USERNAME=default\nREDIS_PASSWORD=\(password)\n"
        }
        return "DB_CONNECTION=\(engine == .mysql ? "mysql" : "pgsql")\nDB_HOST=127.0.0.1\nDB_PORT=\(port)\nDB_DATABASE=\(database)\nDB_USERNAME=\(username)\nDB_PASSWORD=\(password)\n"
    }
}

/// Owns each database process and data directory independently of the web
/// environment. No privileged helper or external service is used.
public actor DatabaseManager {
    private struct Identity: Codable, Equatable {
        let serviceID: UUID
        let runtimeID: String
        let engine: DatabaseEngine
        let version: String
    }
    private struct ActiveRun: Codable {
        let processID: Int32
        let runtimeID: String
    }
    private struct Running {
        let token: UUID
        let processID: Int32
        let sockets: URL
    }
    public let directory: URL
    private let store: DatabaseStore
    private let processes: ProcessSupervisor
    private let commands: any CommandRunning
    private var configuration = DatabaseConfiguration()
    private var statuses: [UUID: DatabaseStatus] = [:]
    private var running: [UUID: Running] = [:]
    private var operations: Set<UUID> = []
    private var locks: [UUID: Int32] = [:]
    private var loaded = false
    private var changingConfiguration = false

    public init(directory: URL, commands: any CommandRunning = LocalCommandRunner(), processes: ProcessSupervisor = ProcessSupervisor()) {
        self.directory = directory
        self.store = DatabaseStore(directory: directory)
        self.commands = commands
        self.processes = processes
    }

    public func load() async throws -> DatabaseConfiguration {
        guard !loaded else { return configuration }
        guard !changingConfiguration else { throw JerdError.unavailable("Database settings are busy.") }
        changingConfiguration = true
        defer { changingConfiguration = false }
        try PrivateFiles.directory(directory)
        configuration = try await store.load()
        loaded = true
        return configuration
    }

    public func registerRuntimes(_ runtimes: [DatabaseRuntime]) async throws {
        try requireLoaded()
        var next = configuration
        for runtime in runtimes {
            if let existing = next.runtimes.first(where: { $0.id == runtime.id }) {
                guard existing == runtime else { throw JerdError.invalid("The installed database runtime changed under the same ID.") }
            } else { next.runtimes.append(runtime) }
        }
        if next != configuration { try await save(next) }
    }

    public func suggestedPort(for engine: DatabaseEngine) async throws -> UInt16 {
        try requireLoaded()
        return try await LocalServicePorts(directory: directory, commands: commands)
            .suggest(startingAt: engine.defaultPort, excluding: Set(configuration.services.map(\.port)))
    }

    public func add(name: String, runtimeID: String, port: UInt16) async throws -> DatabaseService {
        try requireLoaded()
        try await requirePortAvailable(port)
        let service = DatabaseService(name: name.trimmingCharacters(in: .whitespacesAndNewlines), runtimeID: runtimeID, port: port)
        var next = configuration
        next.services.append(service)
        try await save(next)
        statuses[service.id] = DatabaseStatus()
        return service
    }

    public func edit(_ service: DatabaseService) async throws {
        let old = try lookup(service.id)
        guard old.runtimeID == service.runtimeID, running[service.id] == nil, !operations.contains(service.id) else {
            throw JerdError.unavailable("Stop the service before editing it. Its database version cannot be changed.")
        }
        operations.insert(service.id)
        defer { operations.remove(service.id) }
        if old.port != service.port { try await requirePortAvailable(service.port) }
        var next = configuration
        next.services[next.services.firstIndex(where: { $0.id == service.id })!] = service
        try await save(next)
    }

    public func remove(_ id: UUID) async throws {
        _ = try lookup(id)
        try begin(id)
        defer { operations.remove(id) }
        if running[id] == nil { try checkPreviousRun(DatabasePaths(directory: directory, serviceID: id)) }
        try await stopOwned(id)
        var next = configuration
        next.services.removeAll { $0.id == id }
        try await save(next)
        statuses[id] = nil
        // Database files and credentials are deliberately retained.
    }

    public func start(_ id: UUID) async throws {
        let service = try lookup(id)
        let runtime = try configuration.runtime(for: service)
        guard running[id] == nil else { throw JerdError.unavailable("This database service already has a process. Stop it before retrying.") }
        try begin(id)
        defer { operations.remove(id) }
        statuses[id] = DatabaseStatus(state: .starting)
        let paths = DatabasePaths(directory: directory, serviceID: id)
        do {
            try await requirePortAvailable(service.port)
            try prepareRoot(paths)
            try acquireLock(id, paths: paths)
            try checkPreviousRun(paths)
            try await verifyRuntime(runtime, paths: paths)
            let identity = Identity(serviceID: id, runtimeID: runtime.id, engine: runtime.engine, version: runtime.version)
            try checkIdentity(identity, paths: paths)
            let credentials = try credentials(paths: paths)
            try await initialize(identity: identity, runtime: runtime, service: service, paths: paths, credentials: credentials)
            try await launch(runtime: runtime, service: service, paths: paths, credentials: credentials)
            try await waitUntilReady(runtime: runtime, service: service, paths: paths, credentials: credentials)
            try await verifyListeners(id: id, port: service.port, paths: paths)
            guard let process = running[id], await processes.isRunning(process.token) else {
                throw JerdError.process("The database exited during its readiness check.")
            }
            statuses[id] = DatabaseStatus(state: .running, processID: process.processID)
        } catch {
            var detail = error.localizedDescription
            do { try await stopOwned(id) }
            catch { detail += " " + error.localizedDescription }
            if running[id] == nil { releaseLock(id) }
            statuses[id] = DatabaseStatus(state: .failed(detail), processID: running[id]?.processID)
            throw JerdError.process(detail)
        }
    }

    public func stop(_ id: UUID) async throws {
        _ = try lookup(id)
        try begin(id)
        defer { operations.remove(id) }
        statuses[id] = DatabaseStatus(state: .stopping, processID: running[id]?.processID)
        do {
            try await stopOwned(id)
            statuses[id] = DatabaseStatus()
        } catch {
            statuses[id] = DatabaseStatus(state: .failed(error.localizedDescription), processID: running[id]?.processID)
            throw error
        }
    }

    public func stopAll() async throws {
        guard operations.isEmpty else { throw JerdError.unavailable("Wait for the current database operation to finish before quitting.") }
        var failures: [String] = []
        for id in Array(running.keys) {
            do { try await stop(id) }
            catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { throw JerdError.process(failures.joined(separator: "\n")) }
    }

    public func snapshot() async -> DatabaseSnapshot {
        for (id, process) in running where !operations.contains(id) {
            let alive = await processes.isRunning(process.token)
            if !alive, !operations.contains(id), running[id]?.token == process.token {
                operations.insert(id)
                let paths = DatabasePaths(directory: directory, serviceID: id)
                let detail = "The database process exited. " + logTail(paths)
                _ = await processes.stopGracefully(process.token)
                cleanup(id, process: process, paths: paths)
                statuses[id] = DatabaseStatus(state: .failed(detail))
                operations.remove(id)
            }
        }
        return DatabaseSnapshot(configuration: configuration, statuses: statuses)
    }

    public func connection(for id: UUID) throws -> DatabaseConnection {
        let service = try lookup(id)
        let runtime = try configuration.runtime(for: service)
        let paths = DatabasePaths(directory: directory, serviceID: id)
        guard FileManager.default.fileExists(atPath: paths.credentials.path) else {
            throw JerdError.unavailable("Start the service once to create its credentials.")
        }
        let value = try JSONDecoder().decode(DatabaseCredentials.self, from: Data(contentsOf: paths.credentials))
        try value.validate()
        return DatabaseConnection(engine: runtime.engine, port: service.port, password: value.password)
    }

    private func lookup(_ id: UUID) throws -> DatabaseService {
        try requireLoaded()
        guard let service = configuration.services.first(where: { $0.id == id }) else { throw JerdError.invalid("The database service is not registered.") }
        return service
    }
    private func requireLoaded() throws {
        guard loaded else { throw JerdError.unavailable("Load database settings before changing services.") }
    }
    private func begin(_ id: UUID) throws {
        guard operations.insert(id).inserted else { throw JerdError.unavailable("This database service is busy.") }
    }
    private func save(_ next: DatabaseConfiguration) async throws {
        guard !changingConfiguration else { throw JerdError.unavailable("Database settings are busy.") }
        changingConfiguration = true
        defer { changingConfiguration = false }
        try await store.save(next)
        configuration = next
    }

    private func prepareRoot(_ paths: DatabasePaths) throws {
        for folder in [directory, directory.appendingPathComponent("instances"), paths.root] { try PrivateFiles.directory(folder) }
    }
    private func acquireLock(_ id: UUID, paths: DatabasePaths) throws {
        guard locks[id] == nil else { throw JerdError.unavailable("This database instance is already in use.") }
        let path = paths.root.appendingPathComponent("service.lock")
        let descriptor = Darwin.open(path.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw JerdError.unavailable("Cannot lock the database instance.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw JerdError.unavailable("Another Jerd process is using this database instance.")
        }
        locks[id] = descriptor
    }
    private func releaseLock(_ id: UUID) {
        if let descriptor = locks.removeValue(forKey: id) { _ = flock(descriptor, LOCK_UN); close(descriptor) }
    }
    private func activeRunURL(_ paths: DatabasePaths) -> URL { paths.root.appendingPathComponent("active-run.json") }
    private func checkPreviousRun(_ paths: DatabasePaths) throws {
        let url = activeRunURL(paths)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let previous = try JSONDecoder().decode(ActiveRun.self, from: Data(contentsOf: url))
        guard previous.processID > 1 else { throw JerdError.corruptConfiguration("The previous database process record is invalid.") }
        if kill(previous.processID, 0) == 0 || errno == EPERM {
            throw JerdError.unavailable("A previous database process (PID \(previous.processID)) is still present. Stop it safely before restarting this instance. Jerd did not signal it.")
        }
        try FileManager.default.removeItem(at: url)
    }
    private func checkIdentity(_ expected: Identity, paths: DatabasePaths) throws {
        if FileManager.default.fileExists(atPath: paths.identity.path) {
            let actual = try JSONDecoder().decode(Identity.self, from: Data(contentsOf: paths.identity))
            guard actual == expected else { throw JerdError.invalid("This data directory belongs to a different database version. It was preserved.") }
        } else {
            guard !FileManager.default.fileExists(atPath: paths.data.path) else {
                throw JerdError.invalid("An untracked database directory already exists. It was preserved.")
            }
            try PrivateFiles.write(JSONEncoder().encode(expected), to: paths.identity)
        }
    }
    private func credentials(paths: DatabasePaths) throws -> DatabaseCredentials {
        if FileManager.default.fileExists(atPath: paths.credentials.path) {
            let value = try JSONDecoder().decode(DatabaseCredentials.self, from: Data(contentsOf: paths.credentials))
            try value.validate()
            return value
        }
        guard !FileManager.default.fileExists(atPath: paths.data.path) else {
            throw JerdError.corruptConfiguration("The database credentials are missing. Existing data was preserved.")
        }
        let value = try DatabaseCredentials()
        try PrivateFiles.write(JSONEncoder().encode(value), to: paths.credentials)
        return value
    }

    private func verifyRuntime(_ runtime: DatabaseRuntime, paths: DatabasePaths) async throws {
        let version = try await commands.run(ProcessRequest(executable: runtime.executable(runtime.engine.serverName),
            arguments: ["--version"], directory: paths.root), timeout: .seconds(10))
        let escaped = NSRegularExpression.escapedPattern(for: runtime.version)
        guard version.status == 0, version.output.range(of: "(?<![0-9.])" + escaped + "(?![0-9.])", options: .regularExpression) != nil else {
            throw JerdError.unavailable("The database executable does not match the registered version.")
        }
    }

    private func initialize(identity: Identity, runtime: DatabaseRuntime, service: DatabaseService, paths: DatabasePaths,
                            credentials: DatabaseCredentials) async throws {
        let exists = FileManager.default.fileExists(atPath: paths.data.path)
        if FileManager.default.fileExists(atPath: paths.initialized.path) {
            let stored = try JSONDecoder().decode(Identity.self, from: Data(contentsOf: paths.initialized))
            let info = try paths.data.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard stored == identity, exists, info.isDirectory == true, info.isSymbolicLink != true else {
                throw JerdError.corruptConfiguration("The initialized database directory is missing or does not match this service.")
            }
            return
        }
        guard !exists else {
            throw JerdError.corruptConfiguration("Database initialization was interrupted. The partial data was preserved. Inspect the data folder before creating a new service.")
        }
        let passwordFile = paths.root.appendingPathComponent("init-password")
        defer { try? FileManager.default.removeItem(at: passwordFile) }
        if runtime.engine == .postgresql { try PrivateFiles.write(Data((credentials.password + "\n").utf8), to: passwordFile) }
        if let request = DatabaseDriver.initialization(runtime: runtime, paths: paths) {
            let result = try await commands.run(request, timeout: .seconds(120))
            guard result.status == 0 else {
                throw JerdError.process("Database initialization failed: " + result.output.suffix(4096).replacingOccurrences(of: credentials.password, with: "[redacted]"))
            }
        } else { try PrivateFiles.directory(paths.data) }
        if runtime.engine == .mysql {
            defer {
                try? FileManager.default.removeItem(at: paths.root.appendingPathComponent("bootstrap.sql"))
                try? FileManager.default.removeItem(at: paths.root.appendingPathComponent("bootstrap.cnf"))
            }
            try await launch(runtime: runtime, service: service, paths: paths, credentials: credentials, bootstrap: true)
            try await waitUntilReady(runtime: runtime, service: service, paths: paths, credentials: credentials, bootstrap: true)
            try await verifyListeners(id: service.id, port: nil, paths: paths)
            try await stopOwned(service.id, releaseInstanceLock: false)
        }
        try PrivateFiles.write(JSONEncoder().encode(identity), to: paths.initialized)
    }

    private func launch(runtime: DatabaseRuntime, service: DatabaseService, paths: DatabasePaths,
                        credentials: DatabaseCredentials, bootstrap: Bool = false) async throws {
        let sockets = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-db-\(UUID().uuidString.prefix(10))")
        guard !FileManager.default.fileExists(atPath: sockets.path), sockets.path.utf8.count + 20 < 104 else {
            throw JerdError.invalid("Cannot create a private database socket directory.")
        }
        try PrivateFiles.directory(sockets)
        var ownsProcess = false
        defer { if !ownsProcess { try? FileManager.default.removeItem(at: sockets) } }
        try DatabaseDriver.writeConfiguration(runtime: runtime, service: service, paths: paths, credentials: credentials, sockets: sockets)
        if bootstrap { try DatabaseDriver.writeBootstrap(paths: paths, credentials: credentials, sockets: sockets) }
        if FileManager.default.fileExists(atPath: paths.log.path) {
            let previous = paths.root.appendingPathComponent("server.previous.log")
            if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
            try FileManager.default.moveItem(at: paths.log, to: previous)
        }
        let token = try await processes.start(DatabaseDriver.server(runtime: runtime, service: service, paths: paths,
                                                                    sockets: sockets, bootstrap: bootstrap), log: paths.log)
        guard let pid = await processes.processIdentifier(token) else {
            _ = await processes.stopGracefully(token)
            throw JerdError.process("The database process could not start. " + logTail(paths))
        }
        running[service.id] = Running(token: token, processID: pid, sockets: sockets)
        ownsProcess = true
        statuses[service.id]?.processID = pid
        try PrivateFiles.write(JSONEncoder().encode(ActiveRun(processID: pid, runtimeID: runtime.id)), to: activeRunURL(paths))
    }

    private func waitUntilReady(runtime: DatabaseRuntime, service: DatabaseService, paths: DatabasePaths,
                                credentials: DatabaseCredentials, bootstrap: Bool = false) async throws {
        let deadline = ContinuousClock.now + .seconds(45)
        var lastFailure = "No response from the database."
        while ContinuousClock.now < deadline {
            guard let process = running[service.id], await processes.isRunning(process.token) else {
                throw JerdError.process("The database exited before it was ready. " + logTail(paths))
            }
            do {
                let result = try await commands.run(DatabaseDriver.healthCheck(runtime: runtime, service: service, paths: paths,
                    credentials: credentials, bootstrap: bootstrap), timeout: .seconds(2))
                let expected = runtime.engine == .redis ? "PONG" : "42"
                if result.status == 0, result.output.trimmingCharacters(in: .whitespacesAndNewlines) == expected { return }
                lastFailure = String(result.output.suffix(1024)).replacingOccurrences(of: credentials.password, with: "[redacted]")
            } catch { lastFailure = error.localizedDescription }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw JerdError.process("Database readiness timed out. " + lastFailure)
    }

    private func verifyListeners(id: UUID, port: UInt16?, paths: DatabasePaths) async throws {
        guard let process = running[id] else { throw JerdError.process("The database process is missing.") }
        try await LocalServicePorts(directory: paths.root, commands: commands)
            .verify(processID: process.processID, ports: Set(port.map { [$0] } ?? []))
    }

    private func requirePortAvailable(_ port: UInt16) async throws {
        try await LocalServicePorts(directory: directory, commands: commands).requireAvailable(port)
    }

    private func stopOwned(_ id: UUID, releaseInstanceLock: Bool = true) async throws {
        guard let process = running[id] else {
            if releaseInstanceLock { releaseLock(id) }
            return
        }
        let service = try lookup(id)
        let runtime = try configuration.runtime(for: service)
        let signal = runtime.engine == .postgresql ? SIGINT : SIGTERM
        guard await processes.stopGracefully(process.token, signal: signal) else {
            throw JerdError.process("\(service.name) did not stop within 30 seconds. Its process is still tracked. Retry Stop; Jerd did not force it to exit.")
        }
        cleanup(id, process: process, paths: DatabasePaths(directory: directory, serviceID: id), releaseInstanceLock: releaseInstanceLock)
    }
    private func cleanup(_ id: UUID, process: Running, paths: DatabasePaths, releaseInstanceLock: Bool = true) {
        running[id] = nil
        try? FileManager.default.removeItem(at: process.sockets)
        try? FileManager.default.removeItem(at: activeRunURL(paths))
        if releaseInstanceLock { releaseLock(id) }
    }
    private func logTail(_ paths: DatabasePaths) -> String {
        guard let input = try? FileHandle(forReadingFrom: paths.log) else { return "Open the service log for details." }
        defer { try? input.close() }
        guard let size = try? input.seekToEnd(), (try? input.seek(toOffset: size > 4096 ? size - 4096 : 0)) != nil,
              let data = try? input.read(upToCount: 4096) else { return "Open the service log for details." }
        var text = String(decoding: data, as: UTF8.self)
        if let stored = try? Data(contentsOf: paths.credentials), let value = try? JSONDecoder().decode(DatabaseCredentials.self, from: stored) {
            text = text.replacingOccurrences(of: value.password, with: "[redacted]")
        }
        return text
    }
}
