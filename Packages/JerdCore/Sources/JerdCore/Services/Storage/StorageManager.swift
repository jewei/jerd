import Foundation
import CryptoKit
import Darwin

/// Owns one local RustFS instance. Bucket setup uses a persisted intent so a
/// failed request can be retried without deleting data or losing its name.
public actor StorageManager {
    private struct Running { let token: UUID; let processID: Int32 }
    private struct ActiveRun: Codable { let processID: Int32; let runtimeID: String }
    private struct Initialized: Codable { let runtime: StorageRuntime; let formatHash: String; let credentialsHash: String }
    public let paths: StoragePaths
    private let store: StorageStore
    private let commands: any CommandRunning
    private let processes: ProcessSupervisor
    private var configuration = StorageConfiguration()
    private var state = StorageState.stopped
    private var running: Running?
    private var client: StorageS3Client?
    private var availableBuckets: Set<String> = []
    private var lock: Int32?
    private var loaded = false
    private var busy = false

    public init(directory: URL, commands: any CommandRunning = LocalCommandRunner(), processes: ProcessSupervisor = ProcessSupervisor()) {
        paths = StoragePaths(root: directory)
        store = StorageStore(directory: directory)
        self.commands = commands; self.processes = processes
    }
    private var ports: LocalServicePorts { LocalServicePorts(directory: paths.root, commands: commands) }
    private var updateBackup: ServiceUpdateBackup {
        ServiceUpdateBackup(root: paths.root, names: ["settings.json", "settings.previous.json", "data", "runtime.json", "initialized.json",
            "credentials.json", "access-key", "secret-key"])
    }

    public func load() async throws -> StorageConfiguration {
        if loaded { return configuration }
        try begin(allowUpdateRecovery: true); defer { busy = false }
        try await recoverUpdate()
        configuration = try await store.load()
        try PrivateFiles.directory(paths.root)
        loaded = true
        return configuration
    }
    public func registerRuntime(_ runtime: StorageRuntime) async throws {
        try requireLoaded(); try begin(); defer { busy = false }
        if let existing = configuration.runtime {
            guard existing == runtime else { throw JerdError.invalid("The RustFS runtime changed. Stored objects were preserved.") }
            return
        }
        var next = configuration
        next.runtime = runtime
        next.apiPort = try await ports.suggest(startingAt: 9000)
        next.consolePort = try await ports.suggest(startingAt: 9001, excluding: [next.apiPort])
        try await save(next)
    }
    public func suggestedPorts() async throws -> (api: UInt16, console: UInt16) {
        try requireLoaded()
        let api = try await ports.suggest(startingAt: 9000)
        return (api, try await ports.suggest(startingAt: 9001, excluding: [api]))
    }
    public func edit(apiPort: UInt16, consolePort: UInt16) async throws {
        try requireLoaded(); try begin(); defer { busy = false }
        guard running == nil else { throw JerdError.unavailable("Stop storage before changing its ports.") }
        try checkPreviousRun()
        var next = configuration
        next.apiPort = apiPort; next.consolePort = consolePort
        try next.validate()
        try await ports.requireAvailable(apiPort); try await ports.requireAvailable(consolePort)
        try await save(next)
        state = .stopped
    }
    public func start() async throws {
        try requireLoaded(); try begin(allowUpdateRecovery: true); defer { busy = false }
        try await recoverUpdate()
        try await startOwned()
    }
    public func stop() async throws {
        try requireLoaded(); try begin(allowUpdateRecovery: true); defer { busy = false }
        state = .stopping
        do { try await stopOwned(); state = .stopped }
        catch { state = .failed(error.localizedDescription); throw error }
    }
    public func addBucket(name: String, publicRead: Bool) async throws {
        try requireLoaded(); try begin(); defer { busy = false }
        try StorageBucket.validateName(name)
        if let existing = configuration.buckets.first(where: { $0.name == name }) {
            guard !existing.setupComplete, existing.publicRead == publicRead else {
                throw JerdError.invalid("A bucket named \(name) is already registered. Select it in Storage.")
            }
        }
        if running == nil { try await startOwned() }
        let client = try await readyClient()
        if !configuration.buckets.contains(where: { $0.name == name }) {
            guard try await !client.bucketExists(name) else {
                throw JerdError.invalid("A bucket named \(name) already exists in RustFS. No settings were changed.")
            }
            var next = configuration
            next.buckets.append(StorageBucket(name: name, publicRead: publicRead))
            try await save(next)
        }
        try await provision(name: name, client: client)
    }
    public func retryBucket(_ name: String) async throws {
        try requireLoaded(); try begin(); defer { busy = false }
        guard let bucket = configuration.buckets.first(where: { $0.name == name }), !bucket.setupComplete else {
            throw JerdError.invalid("Only an unfinished bucket setup can be retried.")
        }
        if running == nil { try await startOwned() }
        try await provision(name: name, client: readyClient())
    }
    public func refreshBuckets() async throws {
        try requireLoaded(); try begin(); defer { busy = false }
        let client = try await readyClient()
        availableBuckets = try await client.listBuckets()
    }
    public func credentials() throws -> StorageCredentials {
        try requireLoaded()
        return try readCredentials()
    }
    public func snapshot() async -> StorageSnapshot {
        if !busy, let process = running {
            let alive = await processes.isRunning(process.token)
            if !alive, !busy, running?.token == process.token {
                busy = true
                _ = await processes.stopGracefully(process.token)
                cleanup()
                state = .failed("The RustFS process exited. Open the storage log for details.")
                busy = false
            }
        }
        return StorageSnapshot(configuration: configuration, state: state, processID: running?.processID,
                               availableBuckets: state == .running ? availableBuckets : [])
    }

    private func provision(name: String, client: StorageS3Client) async throws {
        guard let bucket = configuration.buckets.first(where: { $0.name == name }) else { return }
        if try await !client.bucketExists(name) { try await client.createBucket(name) }
        try await client.configureAccess(bucket)
        guard try await client.bucketExists(name) else { throw JerdError.process("RustFS did not confirm the new bucket. Retry setup.") }
        var next = configuration
        next.buckets[next.buckets.firstIndex(where: { $0.name == name })!].setupComplete = true
        try await save(next)
        availableBuckets.insert(name)
    }
    private func readyClient() async throws -> StorageS3Client {
        guard state == .running, let running, let client, await processes.isRunning(running.token) else {
            throw JerdError.unavailable("Start storage before using its buckets.")
        }
        try await ports.verify(processID: running.processID, ports: [configuration.apiPort, configuration.consolePort])
        return client
    }
    private func startOwned() async throws {
        guard let runtime = configuration.runtime else { throw JerdError.unavailable("The RustFS runtime is not installed.") }
        guard running == nil else { throw JerdError.unavailable("Storage already has a process. Stop it before retrying.") }
        state = .starting
        do {
            try await ports.requireAvailable(configuration.apiPort)
            try await ports.requireAvailable(configuration.consolePort)
            try acquireLock(); try checkPreviousRun()
            let version = try await commands.run(ProcessRequest(executable: runtime.executable,
                arguments: ["--version"], directory: paths.root), timeout: .seconds(10))
            let escaped = NSRegularExpression.escapedPattern(for: runtime.version)
            let pattern = "(?m)^rustfs\\s+v?" + escaped + "(?![0-9.])"
            guard version.status == 0, version.output.range(of: pattern, options: .regularExpression) != nil else {
                throw JerdError.unavailable("The RustFS executable does not match the saved version.")
            }
            let credentials = try prepareData(runtime: runtime)
            if FileManager.default.fileExists(atPath: paths.log.path) {
                let previous = paths.root.appendingPathComponent("server.previous.log")
                if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
                try FileManager.default.moveItem(at: paths.log, to: previous)
            }
            let token = try await processes.start(StorageDriver.server(configuration: configuration, runtime: runtime, paths: paths), log: paths.log)
            guard let pid = await processes.processIdentifier(token) else {
                _ = await processes.stopGracefully(token)
                throw JerdError.process("RustFS could not start. Open the storage log for details.")
            }
            running = Running(token: token, processID: pid)
            try PrivateFiles.write(JSONEncoder().encode(ActiveRun(processID: pid, runtimeID: runtime.id)), to: paths.activeRun)
            client = StorageS3Client(port: configuration.apiPort, region: configuration.region, credentials: credentials)
            try await waitUntilReady()
            try await ports.verify(processID: pid, ports: [configuration.apiPort, configuration.consolePort])
            guard await processes.isRunning(token) else { throw JerdError.process("RustFS exited during its readiness check.") }
            let initialized = try Initialized(runtime: runtime, formatHash: fileHash(paths.format), credentialsHash: fileHash(paths.credentials))
            try PrivateFiles.write(JSONEncoder().encode(initialized), to: paths.initialized)
            state = .running
        } catch {
            var detail = error.localizedDescription
            do { try await stopOwned() } catch { detail += " " + error.localizedDescription }
            if running == nil { releaseLock() }
            state = .failed(detail)
            throw JerdError.process(detail)
        }
    }
    private func prepareData(runtime: StorageRuntime) throws -> StorageCredentials {
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.initialized.path) {
            let initialized = try JSONDecoder().decode(Initialized.self, from: Data(contentsOf: paths.initialized))
            guard initialized.runtime == runtime, try fileHash(paths.format) == initialized.formatHash,
                  try fileHash(paths.credentials) == initialized.credentialsHash else {
                throw JerdError.corruptConfiguration("Storage data or credentials changed, or belong to a different RustFS version. Existing files were preserved.")
            }
        }
        try PrivateFiles.directory(paths.data)
        if fm.fileExists(atPath: paths.identity.path) {
            let previous = try JSONDecoder().decode(StorageRuntime.self, from: Data(contentsOf: paths.identity))
            guard previous == runtime else { throw JerdError.invalid("The data folder belongs to a different RustFS version. It was preserved.") }
        } else {
            guard try fm.contentsOfDirectory(atPath: paths.data.path).isEmpty else {
                throw JerdError.invalid("An untracked storage data folder already exists. It was preserved.")
            }
            try PrivateFiles.write(JSONEncoder().encode(runtime), to: paths.identity)
        }
        let credentials: StorageCredentials
        if fm.fileExists(atPath: paths.credentials.path) { credentials = try readCredentials() }
        else {
            guard try fm.contentsOfDirectory(atPath: paths.data.path).isEmpty else {
                throw JerdError.corruptConfiguration("Storage credentials are missing. Existing data was preserved.")
            }
            credentials = try .generate()
            try PrivateFiles.write(JSONEncoder().encode(credentials), to: paths.credentials)
        }
        try PrivateFiles.write(Data(credentials.accessKey.utf8), to: paths.accessKey)
        try PrivateFiles.write(Data(credentials.secretKey.utf8), to: paths.secretKey)
        return credentials
    }
    private func readCredentials() throws -> StorageCredentials {
        _ = try fileHash(paths.credentials)
        let credentials = try JSONDecoder().decode(StorageCredentials.self, from: Data(contentsOf: paths.credentials))
        try credentials.validate()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.credentials.path)
        return credentials
    }
    private func fileHash(_ file: URL) throws -> String {
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) < 65_536 else {
            throw JerdError.corruptConfiguration("A required storage file is invalid. Existing files were preserved.")
        }
        return SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }
    private func waitUntilReady() async throws {
        let deadline = ContinuousClock.now + .seconds(45)
        while ContinuousClock.now < deadline {
            guard let running, await processes.isRunning(running.token), let client else {
                throw JerdError.process("RustFS exited before it was ready. Open the storage log for details.")
            }
            do {
                availableBuckets = try await client.listBuckets()
                let console = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                    arguments: ["--silent", "--show-error", "--fail", "--max-time", "2", "--noproxy", "*",
                                "--output", "/dev/null", configuration.consoleURL.absoluteString], directory: paths.root), timeout: .seconds(3))
                if console.status == 0 { return }
            } catch { /* Retry while RustFS initializes its storage and S3 handlers. */ }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw JerdError.process("RustFS did not become ready within 45 seconds. Open the storage log for details.")
    }
    private func save(_ next: StorageConfiguration) async throws { try await store.save(next); configuration = next }
    public func updateRuntime(_ runtime: StorageRuntime) async throws {
        try requireLoaded(); try begin(); defer { busy = false }
        guard let previous = configuration.runtime else { throw JerdError.unavailable("The RustFS runtime is not installed.") }
        if runtime == previous { return }
        let wasRunning = running != nil
        state = .stopping
        do { try await stopOwned() }
        catch { state = .failed(error.localizedDescription); throw error }
        state = .stopped
        defer { if running == nil { releaseLock() } }
        do {
            try acquireLock()
            try checkPreviousRun()
            _ = try prepareData(runtime: previous)
            _ = try updateBackup.begin()
            var next = configuration; next.runtime = runtime
            try await store.save(next, replacingRuntime: previous); configuration = next
            try PrivateFiles.write(JSONEncoder().encode(runtime), to: paths.identity)
            if FileManager.default.fileExists(atPath: paths.initialized.path) {
                let initialized = try Initialized(runtime: runtime, formatHash: fileHash(paths.format), credentialsHash: fileHash(paths.credentials))
                try PrivateFiles.write(JSONEncoder().encode(initialized), to: paths.initialized)
            }
            try await startOwned()
            guard Set(configuration.buckets.filter(\.setupComplete).map(\.name)).isSubset(of: availableBuckets) else {
                throw JerdError.process("The updated storage service did not return all registered buckets.")
            }
            if !wasRunning { try await stopOwned(keepLock: true); state = .stopped }
            try updateBackup.commit()
        } catch {
            let failure = error.localizedDescription
            do {
                try await stopOwned(); try await recoverUpdate()
                if wasRunning { try await startOwned() } else { state = .stopped }
            } catch {
                state = .failed("Storage update failed. \(failure) Recovery: \(error.localizedDescription)")
                throw JerdError.process("Storage update failed. Backup files were preserved. \(error.localizedDescription)")
            }
            throw JerdError.process("Storage update failed. The previous runtime and data were restored. \(failure)")
        }
    }
    private func recoverUpdate() async throws {
        guard updateBackup.isPending else { return }
        guard running == nil else { throw JerdError.unavailable("Stop storage before recovering its runtime update.") }
        try acquireLock(); defer { releaseLock() }
        try checkPreviousRun()
        try updateBackup.restoreIfNeeded()
        configuration = try await store.load()
    }
    private func begin(allowUpdateRecovery: Bool = false) throws {
        guard !busy else { throw JerdError.unavailable("Wait for the current storage operation to finish.") }
        guard allowUpdateRecovery || !updateBackup.isPending else { throw JerdError.unavailable("Stop and start storage to recover its unfinished runtime update.") }
        busy = true
    }
    private func requireLoaded() throws {
        guard loaded else { throw JerdError.unavailable("Load storage settings before changing the service.") }
    }
    private func acquireLock() throws {
        if lock != nil { return }
        let descriptor = Darwin.open(paths.root.appendingPathComponent("service.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw JerdError.unavailable("Cannot lock the storage data folder.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw JerdError.unavailable("Another Jerd process is using this storage data folder.")
        }
        lock = descriptor
    }
    private func releaseLock() {
        if let lock { _ = flock(lock, LOCK_UN); close(lock); self.lock = nil }
    }
    private func checkPreviousRun() throws {
        guard FileManager.default.fileExists(atPath: paths.activeRun.path) else { return }
        let previous = try JSONDecoder().decode(ActiveRun.self, from: Data(contentsOf: paths.activeRun))
        guard previous.processID > 1 else { throw JerdError.corruptConfiguration("The previous storage process record is invalid.") }
        if kill(previous.processID, 0) == 0 || errno == EPERM {
            throw JerdError.unavailable("A previous storage process (PID \(previous.processID)) is still present. Stop it safely before restarting. Jerd did not signal it.")
        }
        try FileManager.default.removeItem(at: paths.activeRun)
    }
    private func stopOwned(keepLock: Bool = false) async throws {
        guard let running else { if !keepLock { releaseLock() }; return }
        guard await processes.stopGracefully(running.token) else {
            throw JerdError.process("RustFS did not stop within 30 seconds. Its process is still tracked. Retry Stop; Jerd did not force it to exit.")
        }
        cleanup(keepLock: keepLock)
    }
    private func cleanup(keepLock: Bool = false) {
        running = nil
        client?.close(); client = nil
        availableBuckets = []
        try? FileManager.default.removeItem(at: paths.activeRun)
        if !keepLock { releaseLock() }
    }
}
