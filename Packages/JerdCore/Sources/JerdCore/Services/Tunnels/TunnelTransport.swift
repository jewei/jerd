import Foundation
import Darwin

public struct TunnelProcess: Sendable, Equatable {
    public let id: UUID
    public let processID: Int32
    public init(id: UUID, processID: Int32) { self.id = id; self.processID = processID }
}

public protocol TunnelTransport: Sendable {
    func inspectRuntime(executable: URL, directory: URL) async throws -> TunnelRuntime
    func availablePort(startingAt: UInt16, excluding: Set<UInt16>, directory: URL) async throws -> UInt16
    func start(runtime: TunnelRuntime, registration: TunnelRegistration, token: String, paths: TunnelPaths) async throws -> TunnelProcess
    func ownedProcess(registrationID: UUID) async -> TunnelProcess?
    func isRunning(_ process: TunnelProcess) async -> Bool
    func isReady(_ process: TunnelProcess, registration: TunnelRegistration, paths: TunnelPaths) async throws -> Bool
    func stop(_ process: TunnelProcess, paths: TunnelPaths) async throws
}

public enum TunnelTransportError: Error, Sendable {
    case unexpectedListener
}

struct TunnelTokenPayload: Decodable {
    let a: String
    let t: UUID
    let s: String
    static func decode(_ token: String) -> Self? {
        guard let data = Data(base64Encoded: token) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

public enum TunnelDriver {
    public static func server(runtime: TunnelRuntime, registration: TunnelRegistration, token: String, paths: TunnelPaths) -> ProcessRequest {
        ProcessRequest(executable: runtime.executable, arguments: [
            "tunnel", "--config", paths.config.path, "--no-autoupdate", "--metrics", "127.0.0.1:\(registration.metricsPort)",
            "--grace-period", "15s", "run"
        ], directory: paths.root, environment: ["HOME": paths.home.path, "TUNNEL_TOKEN": token], redactedValues: redactedValues(token))
    }
    public static func redactedValues(_ token: String) -> [String] {
        var values = [token]
        if let payload = TunnelTokenPayload.decode(token), !payload.s.isEmpty { values.append(payload.s) }
        return values
    }
    static func authenticationFailed(_ log: String) -> Bool {
        let text = log.lowercased()
        return ["provided tunnel token is not valid", "invalid tunnel token", "failed to decode token", "unauthorized", "invalid tunnel secret", "authentication failed", "tunnel credentials are invalid"].contains { text.contains($0) }
    }
}

/// Owns only children started here. The fixed config disables global and user config discovery.
public actor TunnelLocalTransport: TunnelTransport {
    private let commands: any CommandRunning
    private let processes: ProcessSupervisor
    private var locks: [UUID: Int32] = [:]
    private var retained: [UUID: TunnelProcess] = [:]
    public init(commands: any CommandRunning = LocalCommandRunner(), processes: ProcessSupervisor = ProcessSupervisor()) {
        self.commands = commands; self.processes = processes
    }
    public func inspectRuntime(executable: URL, directory: URL) async throws -> TunnelRuntime {
        guard executable.isFileURL, executable.lastPathComponent == "cloudflared", FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw JerdError.invalid("Select an executable named cloudflared.")
        }
        try PrivateFiles.directory(directory)
        let result = try await commands.run(ProcessRequest(executable: executable, arguments: ["--version"], directory: directory), timeout: .seconds(10))
        guard result.status == 0, let range = result.output.range(of: #"(?m)^cloudflared version ([0-9]+\.[0-9]+\.[0-9]+)(?=\s|$)"#, options: .regularExpression) else {
            throw JerdError.invalid("The selected executable did not report a cloudflared version.")
        }
        let version = String(result.output[range]).replacingOccurrences(of: "cloudflared version ", with: "")
        return TunnelRuntime(id: "cloudflared-\(version)", version: version, path: executable.deletingLastPathComponent().path)
    }
    public func availablePort(startingAt: UInt16, excluding: Set<UInt16>, directory: URL) async throws -> UInt16 {
        try PrivateFiles.directory(directory)
        return try await LocalServicePorts(directory: directory, commands: commands).suggest(startingAt: startingAt, excluding: excluding)
    }
    public func start(runtime: TunnelRuntime, registration: TunnelRegistration, token: String, paths: TunnelPaths) async throws -> TunnelProcess {
        guard retained[registration.id] == nil, locks[registration.id] == nil else { throw JerdError.unavailable("The previous tunnel process must stop first.") }
        try PrivateFiles.directory(paths.root)
        try PrivateFiles.directory(paths.home)
        let descriptor = Darwin.open(paths.root.appendingPathComponent("service.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw JerdError.unavailable("Cannot lock the tunnel files.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); throw JerdError.unavailable("Another Jerd session controls this tunnel.")
        }
        locks[registration.id] = descriptor
        do {
            try PreviousProcessRun.requireStopped(at: paths.activeRun)
            let inspected = try await inspectRuntime(executable: runtime.executable, directory: paths.root)
            guard inspected.version == runtime.version else { throw JerdError.unavailable("The cloudflared executable does not match the saved version.") }
            try await LocalServicePorts(directory: paths.root, commands: commands).requireAvailable(registration.metricsPort)
            // An explicit empty configuration also excludes /etc/cloudflared and /usr/local/etc/cloudflared.
            try PrivateFiles.write(Data("{}\n".utf8), to: paths.config)
            try Task.checkCancellation()
            let id = try await processes.start(TunnelDriver.server(runtime: runtime, registration: registration, token: token, paths: paths), log: paths.log)
            guard let pid = await processes.ownedProcessIdentifier(id) else {
                _ = await processes.stopGracefully(id)
                throw JerdError.process("The tunnel process exited before its identity could be checked.")
            }
            let process = TunnelProcess(id: id, processID: pid)
            retained[registration.id] = process
            do { try PreviousProcessRun.record(pid, runtimeID: runtime.id, at: paths.activeRun) }
            catch {
                try await stop(process, paths: paths)
                throw error
            }
            return process
        } catch {
            if retained[registration.id] == nil { unlock(registration.id) }
            throw error
        }
    }
    public func ownedProcess(registrationID: UUID) -> TunnelProcess? { retained[registrationID] }
    public func isRunning(_ process: TunnelProcess) async -> Bool { await processes.isRunning(process.id) }
    public func isReady(_ process: TunnelProcess, registration: TunnelRegistration, paths: TunnelPaths) async throws -> Bool {
        guard retained[registration.id] == process, await processes.isRunning(process.id) else { return false }
        let listeners = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-p", String(process.processID), "-iTCP", "-sTCP:LISTEN", "-Fn"], directory: paths.root), timeout: .seconds(5))
        if listeners.status == 1, listeners.output.isEmpty { return false }
        let actual = Set(listeners.output.split(separator: "\n").filter { $0.hasPrefix("n") }.map { String($0.dropFirst()) })
        guard listeners.status == 0, actual == ["127.0.0.1:\(registration.metricsPort)"] else { throw TunnelTransportError.unexpectedListener }
        // Outbound QUIC uses UDP. The only permitted TCP listener is this owned metrics port.
        let owners = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-iTCP:\(registration.metricsPort)", "-sTCP:LISTEN", "-Fp"], directory: paths.root), timeout: .seconds(5))
        let ownerIDs = Set(owners.output.split(separator: "\n").filter { $0.hasPrefix("p") }.compactMap { Int32($0.dropFirst()) })
        guard owners.status == 0, ownerIDs == [process.processID] else { throw TunnelTransportError.unexpectedListener }
        let result = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"), arguments: [
            "--silent", "--show-error", "--max-time", "2", "--noproxy", "*", "--output", "/dev/null", "--write-out", "%{http_code}",
            "--url", "http://127.0.0.1:\(registration.metricsPort)/ready"
        ], directory: paths.root), timeout: .seconds(3))
        guard await processes.isRunning(process.id) else { return false }
        return result.status == 0 && result.output == "200"
    }
    public func stop(_ process: TunnelProcess, paths: TunnelPaths) async throws {
        guard let entry = retained.first(where: { $0.value == process }) else { return }
        guard await processes.stopGracefully(process.id) else {
            throw JerdError.process("The tunnel has not stopped. Its process is still tracked. Retry Stop; Jerd did not force it to exit.")
        }
        // Another Stop can finish while this call waits for the supervisor.
        guard retained[entry.key] == process else { return }
        retained[entry.key] = nil
        try? FileManager.default.removeItem(at: paths.activeRun)
        unlock(entry.key)
    }
    private func unlock(_ id: UUID) {
        guard let descriptor = locks.removeValue(forKey: id) else { return }
        _ = flock(descriptor, LOCK_UN); close(descriptor)
    }
}
