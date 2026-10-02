import Foundation
import Darwin

/// Owns one persistent local inbox, independently of sites and databases.
public actor MailManager {
    private struct Running { let token: UUID; let processID: Int32 }
    private struct ActiveRun: Codable { let processID: Int32; let runtimeID: String }
    private struct Info: Decodable {
        let version: String
        let database: String
        enum CodingKeys: String, CodingKey { case version = "Version", database = "Database" }
    }

    public let paths: MailPaths
    private let store: MailStore
    private let commands: any CommandRunning
    private let processes: ProcessSupervisor
    private var configuration = MailConfiguration()
    private var state = MailState.stopped
    private var running: Running?
    private var lock: Int32?
    private var loaded = false
    private var busy = false

    public init(directory: URL, commands: any CommandRunning = LocalCommandRunner(), processes: ProcessSupervisor = ProcessSupervisor()) {
        paths = MailPaths(root: directory)
        store = MailStore(directory: directory)
        self.commands = commands
        self.processes = processes
    }
    private var ports: LocalServicePorts { LocalServicePorts(directory: paths.root, commands: commands) }
    private var updateBackup: ServiceUpdateBackup {
        ServiceUpdateBackup(root: paths.root, names: ["settings.json", "settings.previous.json", "inbox"])
    }

    public func load() async throws -> MailConfiguration {
        if loaded { return configuration }
        try begin(allowUpdateRecovery: true)
        defer { busy = false }
        try await recoverUpdate()
        configuration = try await store.load()
        try PrivateFiles.directory(paths.root)
        loaded = true
        return configuration
    }

    public func registerRuntime(_ runtime: MailRuntime) async throws {
        try requireLoaded()
        try begin()
        defer { busy = false }
        if let existing = configuration.runtime {
            guard existing == runtime else { throw JerdError.invalid("The Mailpit runtime changed. The existing inbox was preserved.") }
            return
        }
        var next = configuration
        next.runtime = runtime
        next.smtpPort = try await ports.suggest(startingAt: 1025)
        next.webPort = try await ports.suggest(startingAt: 8025, excluding: [next.smtpPort])
        try await store.save(next)
        configuration = next
    }

    public func suggestedPorts() async throws -> (smtp: UInt16, web: UInt16) {
        try requireLoaded()
        let smtp = try await ports.suggest(startingAt: 1025)
        return (smtp, try await ports.suggest(startingAt: 8025, excluding: [smtp]))
    }

    public func edit(smtpPort: UInt16, webPort: UInt16) async throws {
        try requireLoaded()
        try begin()
        defer { busy = false }
        guard running == nil else { throw JerdError.unavailable("Stop the mail service before changing its ports.") }
        try checkPreviousRun()
        var next = configuration
        next.smtpPort = smtpPort; next.webPort = webPort
        try next.validate()
        try await ports.requireAvailable(smtpPort)
        try await ports.requireAvailable(webPort)
        try await store.save(next)
        configuration = next
        state = .stopped
    }

    public func start() async throws {
        try requireLoaded()
        try begin(allowUpdateRecovery: true)
        defer { busy = false }
        try await recoverUpdate()
        try await startOwned()
    }

    private func startOwned() async throws {
        guard let runtime = configuration.runtime else { throw JerdError.unavailable("The Mailpit runtime is not installed.") }
        guard running == nil else { throw JerdError.unavailable("The mail service already has a process. Stop it before retrying.") }
        state = .starting
        do {
            try await ports.requireAvailable(configuration.smtpPort)
            try await ports.requireAvailable(configuration.webPort)
            try acquireLock()
            try checkPreviousRun()
            let version = try await commands.run(ProcessRequest(executable: runtime.executable,
                arguments: ["version", "--no-release-check"], directory: paths.root), timeout: .seconds(10))
            let escaped = NSRegularExpression.escapedPattern(for: runtime.version)
            let path = NSRegularExpression.escapedPattern(for: runtime.executable.path)
            let pattern = "(?m)^" + path + "\\s+v?" + escaped + "(?![0-9.])"
            guard version.status == 0, version.output.range(of: pattern, options: .regularExpression) != nil else {
                throw JerdError.unavailable("The Mailpit executable does not match the saved version.")
            }
            try prepareInbox(runtime: runtime)
            if FileManager.default.fileExists(atPath: paths.log.path) {
                let previous = paths.root.appendingPathComponent("server.previous.log")
                if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
                try FileManager.default.moveItem(at: paths.log, to: previous)
            }
            let token = try await processes.start(MailDriver.server(configuration: configuration, runtime: runtime, paths: paths), log: paths.log)
            guard let pid = await processes.processIdentifier(token) else {
                _ = await processes.stopGracefully(token)
                throw JerdError.process("The mail process could not start. " + logTail())
            }
            running = Running(token: token, processID: pid)
            try PrivateFiles.write(JSONEncoder().encode(ActiveRun(processID: pid, runtimeID: runtime.id)), to: paths.activeRun)
            try await waitUntilReady(runtime: runtime)
            try await ports.verify(processID: pid, ports: [configuration.smtpPort, configuration.webPort])
            guard await processes.isRunning(token) else { throw JerdError.process("Mailpit exited during its readiness check.") }
            try PrivateFiles.write(JSONEncoder().encode(runtime), to: paths.initialized)
            state = .running
        } catch {
            var detail = error.localizedDescription
            do { try await stopOwned() } catch { detail += " " + error.localizedDescription }
            if running == nil { releaseLock() }
            state = .failed(detail)
            throw JerdError.process(detail)
        }
    }

    public func stop() async throws {
        try requireLoaded()
        try begin(allowUpdateRecovery: true)
        defer { busy = false }
        state = .stopping
        do { try await stopOwned(); state = .stopped }
        catch { state = .failed(error.localizedDescription); throw error }
    }

    public func snapshot() async -> MailSnapshot {
        if !busy, let process = running {
            let alive = await processes.isRunning(process.token)
            if !alive, !busy, running?.token == process.token {
                busy = true
                _ = await processes.stopGracefully(process.token)
                cleanup()
                state = .failed("The mail process exited. " + logTail())
                busy = false
            }
        }
        return MailSnapshot(configuration: configuration, state: state, processID: running?.processID)
    }

    /// Sends only through the owned local SMTP service. No external relay is configured.
    public func sendTestEmail() async throws {
        try requireLoaded()
        try begin()
        defer { busy = false }
        guard state == .running, let running, await processes.isRunning(running.token) else {
            throw JerdError.unavailable("Start the mail service before sending a test email.")
        }
        try await ports.verify(processID: running.processID, ports: [configuration.smtpPort, configuration.webPort])
        let file = paths.root.appendingPathComponent("test-\(UUID().uuidString).eml")
        defer { try? FileManager.default.removeItem(at: file) }
        let message = [
            "From: Jerd <hello@jerd.test>", "To: Local Inbox <inbox@jerd.test>",
            "Subject: Jerd mail test", "Message-ID: <\(UUID().uuidString)@jerd.test>",
            "MIME-Version: 1.0", "Content-Type: text/plain; charset=UTF-8", "",
            "Jerd captured this message through its local SMTP service.",
            "Open the inbox to inspect messages from your applications.", ""
        ].joined(separator: "\r\n")
        try PrivateFiles.write(Data(message.utf8), to: file)
        let result = try await commands.run(MailDriver.send(configuration: configuration, paths: paths, message: file), timeout: .seconds(7))
        guard result.status == 0 else { throw JerdError.process("The test email could not be sent: " + result.output.suffix(2048)) }
    }

    public func updateRuntime(_ runtime: MailRuntime) async throws {
        try requireLoaded(); try begin(); defer { busy = false }
        guard let previous = configuration.runtime else { throw JerdError.unavailable("The Mailpit runtime is not installed.") }
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
            try prepareInbox(runtime: previous)
            _ = try updateBackup.begin()
            var next = configuration; next.runtime = runtime
            try await store.save(next, replacingRuntime: previous)
            configuration = next
            try PrivateFiles.write(JSONEncoder().encode(runtime), to: paths.identity)
            if FileManager.default.fileExists(atPath: paths.initialized.path) {
                try PrivateFiles.write(JSONEncoder().encode(runtime), to: paths.initialized)
            }
            try await startOwned()
            if !wasRunning { try await stopOwned(keepLock: true); state = .stopped }
            try updateBackup.commit()
        } catch {
            let failure = error.localizedDescription
            do {
                try await stopOwned()
                try await recoverUpdate()
                if wasRunning { try await startOwned() } else { state = .stopped }
            } catch {
                state = .failed("Mail update failed. \(failure) Recovery: \(error.localizedDescription)")
                throw JerdError.process("Mail update failed. Backup files were preserved. \(error.localizedDescription)")
            }
            throw JerdError.process("Mail update failed. The previous runtime and inbox were restored. \(failure)")
        }
    }

    private func recoverUpdate() async throws {
        guard updateBackup.isPending else { return }
        guard running == nil else { throw JerdError.unavailable("Stop mail before recovering its runtime update.") }
        try acquireLock(); defer { releaseLock() }
        try checkPreviousRun()
        try updateBackup.restoreIfNeeded()
        configuration = try await store.load()
    }

    private func begin(allowUpdateRecovery: Bool = false) throws {
        guard !busy else { throw JerdError.unavailable("Wait for the current mail operation to finish.") }
        guard allowUpdateRecovery || !updateBackup.isPending else { throw JerdError.unavailable("Stop and start mail to recover its unfinished runtime update.") }
        busy = true
    }
    private func requireLoaded() throws {
        guard loaded else { throw JerdError.unavailable("Load mail settings before changing the service.") }
    }
    private func acquireLock() throws {
        if lock != nil { return }
        let descriptor = Darwin.open(paths.root.appendingPathComponent("service.lock").path,
                                    O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw JerdError.unavailable("Cannot lock the mail inbox.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw JerdError.unavailable("Another Jerd process is using this mail inbox.")
        }
        lock = descriptor
    }
    private func releaseLock() {
        if let lock { _ = flock(lock, LOCK_UN); close(lock); self.lock = nil }
    }
    private func checkPreviousRun() throws {
        guard FileManager.default.fileExists(atPath: paths.activeRun.path) else { return }
        let previous = try JSONDecoder().decode(ActiveRun.self, from: Data(contentsOf: paths.activeRun))
        guard previous.processID > 1 else { throw JerdError.corruptConfiguration("The previous mail process record is invalid.") }
        if kill(previous.processID, 0) == 0 || errno == EPERM {
            throw JerdError.unavailable("A previous mail process (PID \(previous.processID)) is still present. Stop it safely before restarting. Jerd did not signal it.")
        }
        try FileManager.default.removeItem(at: paths.activeRun)
    }
    private func prepareInbox(runtime: MailRuntime) throws {
        try PrivateFiles.directory(paths.inbox)
        if FileManager.default.fileExists(atPath: paths.initialized.path) {
            let initialized = try JSONDecoder().decode(MailRuntime.self, from: Data(contentsOf: paths.initialized))
            guard initialized == runtime, FileManager.default.fileExists(atPath: paths.database.path) else {
                throw JerdError.corruptConfiguration("The initialized inbox is missing or belongs to a different Mailpit version. Existing files were preserved.")
            }
        }
        if FileManager.default.fileExists(atPath: paths.identity.path) {
            let previous = try JSONDecoder().decode(MailRuntime.self, from: Data(contentsOf: paths.identity))
            guard previous == runtime else { throw JerdError.invalid("The inbox belongs to a different Mailpit version. It was preserved.") }
        } else {
            guard try FileManager.default.contentsOfDirectory(atPath: paths.inbox.path).isEmpty else {
                throw JerdError.invalid("An untracked mail inbox already exists. It was preserved.")
            }
            try PrivateFiles.write(JSONEncoder().encode(runtime), to: paths.identity)
        }
        if FileManager.default.fileExists(atPath: paths.database.path) {
            let info = try paths.database.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else { throw JerdError.invalid("The mail database must be a regular file.") }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.database.path)
        } else { try PrivateFiles.write(Data(), to: paths.database) }
    }
    private func waitUntilReady(runtime: MailRuntime) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline {
            guard let running, await processes.isRunning(running.token) else { throw JerdError.process("Mailpit exited before it was ready. " + logTail()) }
            do {
                let http = try await commands.run(MailDriver.httpProbe(configuration: configuration, paths: paths), timeout: .seconds(3))
                if http.status == 0, let info = try? JSONDecoder().decode(Info.self, from: Data(http.output.utf8)),
                   info.version == "v\(runtime.version)", URL(fileURLWithPath: info.database).standardizedFileURL == paths.database.standardizedFileURL {
                    let smtp = try await commands.run(MailDriver.smtpProbe(configuration: configuration, paths: paths), timeout: .seconds(3))
                    if smtp.status == 0, smtp.output.hasPrefix("250 ") { return }
                }
            } catch { /* Retry transient startup failures within the deadline. */ }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw JerdError.process("Mailpit did not pass its SMTP and web checks. " + logTail())
    }
    private func stopOwned(keepLock: Bool = false) async throws {
        guard let running else { if !keepLock { releaseLock() }; return }
        guard await processes.stopGracefully(running.token) else {
            throw JerdError.process("Mailpit did not stop within 30 seconds. Its process is still tracked. Retry Stop; Jerd did not force it to exit.")
        }
        cleanup(keepLock: keepLock)
    }
    private func cleanup(keepLock: Bool = false) {
        running = nil
        try? FileManager.default.removeItem(at: paths.activeRun)
        if !keepLock { releaseLock() }
    }
    private func logTail() -> String {
        guard let input = try? FileHandle(forReadingFrom: paths.log) else { return "Open the mail log for details." }
        defer { try? input.close() }
        guard let size = try? input.seekToEnd(), (try? input.seek(toOffset: size > 4096 ? size - 4096 : 0)) != nil,
              let data = try? input.read(upToCount: 4096) else { return "Open the mail log for details." }
        return String(decoding: data, as: UTF8.self)
    }
}
