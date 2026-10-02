import Foundation
import Darwin

public enum LoopbackPort {
    /// A preflight check only. The server bind remains authoritative if a race occurs.
    public static func checkAvailable(_ port: UInt16) throws {
        guard port > 1023 else { throw JerdError.invalid("Use an unprivileged test port.") }
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw JerdError.process("Cannot create a port check socket.") }
        defer { close(descriptor) }
        // A stopped server can leave TCP connections in TIME_WAIT. Match the
        // real listener's reuse policy, then also listen to reject another
        // listener on this exact address. LocalServicePorts separately checks
        // wildcard listeners. SO_REUSEPORT is deliberately not enabled.
        var reuse: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw JerdError.process("Cannot configure the port check socket.")
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0, listen(descriptor, 1) == 0 else { throw JerdError.unavailable("Loopback port \(port) is occupied or cannot be bound. No process was stopped.") }
    }
}

public protocol EngineServing: Sendable {
    var state: EnvironmentState { get async }
    func start(sites: [SiteRuntime], caddy: CaddyRuntime, paths: EnginePaths,
               httpsPort: UInt16, httpPort: UInt16, listeningSockets: ListeningSockets?) async throws
    func requestStop() async
    func stop() async
    func preflight(_ configuration: WebConfiguration, paths: EnginePaths) async throws
    func isHealthy() async -> Bool
}

public extension EngineServing {
    func preflight(_ configuration: WebConfiguration, paths: EnginePaths) async throws {}
    func isHealthy() async -> Bool { await state == .running }
    func start(site: Site, runtime: DevelopmentRuntime, caddy: CaddyRuntime, paths: EnginePaths,
               httpsPort: UInt16, httpPort: UInt16, listeningSockets: ListeningSockets? = nil) async throws {
        try await start(sites: [SiteRuntime(site: site, runtime: runtime)], caddy: caddy, paths: paths,
                        httpsPort: httpsPort, httpPort: httpPort, listeningSockets: listeningSockets)
    }
}

/// Runs the unprivileged services. System trust is checked by LocalEnvironment.
public actor ServingEngine: EngineServing {
    public private(set) var state: EnvironmentState = .stopped
    public private(set) var certificate: CertificateState = .notIssued
    public let trust: TrustState = .setupRequired
    private let processes: any ProcessControlling
    private let commands: any CommandRunning
    private let fpmProbe: any FPMProbing
    private let phpTrust: PHPTrustBundle
    private var fpmIDs: [UUID] = []
    private var caddyID: UUID?
    private var activePaths: EnginePaths?
    private var ownsSocketDirectory = false
    private var operation = false
    private var stopRequested = false
    private var monitor: Task<Void, Never>?
    private var recoveryFiles: [UUID: URL] = [:]
    private var activeSockets: [URL] = []
    private var recoveryLock: Int32?

    public init(processes: any ProcessControlling = ProcessSupervisor(),
                commands: any CommandRunning = LocalCommandRunner(), fpmProbe: any FPMProbing = FPMProbe(),
                phpTrust: PHPTrustBundle = PHPTrustBundle()) {
        self.processes = processes
        self.commands = commands
        self.fpmProbe = fpmProbe
        self.phpTrust = phpTrust
    }

    public func preflight(_ configuration: WebConfiguration, paths: EnginePaths) async throws {
        // This directory is separate from the active environment. Caddy validation
        // opens no listeners and never installs system trust.
        try PrivateFiles.directory(paths.configuration)
        try PrivateFiles.directory(paths.logs)
        try PrivateFiles.directory(paths.storage)
        let scan = paths.configuration.appendingPathComponent("empty-ini")
        try PrivateFiles.directory(scan)
        var sites: [Site] = [], sockets: [UUID: URL] = [:], seen: [UUID: DevelopmentRuntime] = [:]
        let provider = DevelopmentRuntimeProvider(runner: commands)
        for entry in configuration.sites {
            try Task.checkCancellation()
            sites.append(try SiteValidator().validate(entry.site, existing: sites, documentRootConfirmed: true))
            sockets[entry.site.id] = paths.socket
            if let previous = seen[entry.runtime.id] {
                guard previous == entry.runtime else { throw JerdError.invalid("A PHP runtime ID has conflicting settings.") }
            } else {
                seen[entry.runtime.id] = entry.runtime
                let runtime = entry.runtime
                let actual = try await provider.inspectPHP(cli: URL(fileURLWithPath: runtime.cliPath), fpm: URL(fileURLWithPath: runtime.fpmPath), workDirectory: paths.configuration)
                guard actual.version == runtime.version, actual.cliExtensions == runtime.cliExtensions, actual.fpmExtensions == runtime.fpmExtensions else {
                    throw JerdError.unavailable("PHP changed since inspection. Inspect and select the runtime again.")
                }
                try PrivateFiles.write(Data(ConfigurationGenerator.fpm(paths: paths).utf8), to: paths.fpmConfig)
                try PrivateFiles.write(Data(ConfigurationGenerator.developmentINI.utf8), to: paths.phpINI)
                try await validate(ProcessRequest(executable: URL(fileURLWithPath: runtime.fpmPath),
                    arguments: ["-c", paths.phpINI.path, "-y", paths.fpmConfig.path, "-t"], directory: paths.root,
                    environment: ["PHP_INI_SCAN_DIR": scan.path]))
            }
        }
        let caddy = configuration.caddy
        guard try await provider.inspectCaddy(binary: URL(fileURLWithPath: caddy.path), workDirectory: paths.configuration).version == caddy.version else {
            throw JerdError.unavailable("Caddy changed since inspection. Select it again.")
        }
        try PrivateFiles.write(ConfigurationGenerator.caddy(sites: sites, sockets: sockets, paths: paths, httpsPort: 18443, httpPort: 18080), to: paths.caddyConfig)
        try await validate(ProcessRequest(executable: URL(fileURLWithPath: caddy.path), arguments: ["validate", "--config", paths.caddyConfig.path],
            directory: paths.root, environment: ["XDG_DATA_HOME": paths.storage.path, "XDG_CONFIG_HOME": paths.configuration.path]))
    }

    public func isHealthy() async -> Bool {
        guard !operation, state == .running, await servicesAreRunning() else { return false }
        for socket in activeSockets {
            do { try await fpmProbe.check(socket: socket) } catch { return false }
        }
        return !operation && state == .running
    }

    public func start(sites: [SiteRuntime], caddy: CaddyRuntime,
                      paths: EnginePaths, httpsPort: UInt16, httpPort: UInt16,
                      listeningSockets: ListeningSockets? = nil) async throws {
        try Task.checkCancellation()
        guard !operation, fpmIDs.isEmpty, caddyID == nil else { throw JerdError.process("The engine is already active.") }
        guard !sites.isEmpty, sites.allSatisfy({ $0.site.isEnabled }) else { throw JerdError.invalid("Enable the sites before starting them.") }
        guard Set(sites.map { $0.site.id }).count == sites.count else { throw JerdError.invalid("The serving plan contains a duplicate site ID.") }
        operation = true
        stopRequested = false
        state = .starting
        certificate = .notIssued
        activePaths = paths
        defer { operation = false }
        do {
            guard geteuid() != 0 else { throw JerdError.process("The serving engine cannot run as root.") }
            var validated: [Site] = []
            for entry in sites {
                validated.append(try SiteValidator().validate(entry.site, existing: validated, documentRootConfirmed: true))
            }
            if let listeningSockets {
                let actual = try listeningSockets.ports()
                guard actual.http == httpPort, actual.https == httpsPort else { throw JerdError.invalid("Listener ports do not match the engine request.") }
            } else {
                try LoopbackPort.checkAvailable(httpsPort)
                try LoopbackPort.checkAvailable(httpPort)
            }
            guard !FileManager.default.fileExists(atPath: paths.socketDirectory.path) else {
                throw JerdError.process("The socket directory already exists. Use a new private run directory; do not remove an unknown socket.")
            }
            try PrivateFiles.directory(paths.root)
            let records = paths.root.appendingPathComponent("processes")
            try PrivateFiles.directory(records)
            let lock = open(records.appendingPathComponent("recovery.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard lock >= 0 else { throw JerdError.unavailable("Cannot lock the web environment.") }
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { close(lock); throw JerdError.unavailable("Another Jerd session is using this web environment.") }
            recoveryLock = lock
            for file in try FileManager.default.contentsOfDirectory(at: records, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
                try PreviousProcessRun.requireStopped(at: file)
            }
            for directory in [paths.configuration, paths.logs, paths.storage, paths.socketDirectory,
                              paths.configuration.appendingPathComponent("empty-ini")] {
                try PrivateFiles.directory(directory)
                if directory == paths.socketDirectory { ownsSocketDirectory = true }
            }
            let provider = DevelopmentRuntimeProvider(runner: commands)
            var pools: [(DevelopmentRuntime, EnginePaths)] = []
            var sockets: [UUID: URL] = [:]
            for entry in sites {
                if let pool = pools.first(where: { $0.0.id == entry.runtime.id }) {
                    guard pool.0 == entry.runtime else { throw JerdError.invalid("A PHP runtime ID has conflicting settings.") }
                    sockets[entry.site.id] = pool.1.socket
                    continue
                }
                let runtime = entry.runtime
                let poolPaths = pools.isEmpty ? paths : EnginePaths(root: paths.root.appendingPathComponent("php/\(runtime.id.uuidString)"),
                    socketDirectory: paths.socketDirectory, installationID: paths.installationID, socketName: "php-\(pools.count).sock")
                for folder in [poolPaths.root, poolPaths.configuration, poolPaths.logs] { try PrivateFiles.directory(folder) }
                let actual = try await provider.inspectPHP(cli: URL(fileURLWithPath: runtime.cliPath),
                                                      fpm: URL(fileURLWithPath: runtime.fpmPath), workDirectory: paths.configuration)
                guard actual.version == runtime.version, actual.cliExtensions == runtime.cliExtensions,
                  actual.fpmExtensions == runtime.fpmExtensions else {
                    throw JerdError.unavailable("PHP changed since inspection. Inspect and select the runtime again.")
                }
                pools.append((runtime, poolPaths))
                sockets[entry.site.id] = poolPaths.socket
            }
            let actualCaddy = try await provider.inspectCaddy(binary: URL(fileURLWithPath: caddy.path), workDirectory: paths.configuration)
            guard actualCaddy.version == caddy.version else { throw JerdError.unavailable("Caddy changed since inspection. Select it again.") }
            try checkStart()
            for (_, poolPaths) in pools {
                try PrivateFiles.write(Data(ConfigurationGenerator.fpm(paths: poolPaths).utf8), to: poolPaths.fpmConfig)
                try PrivateFiles.write(Data(ConfigurationGenerator.developmentINI.utf8), to: poolPaths.phpINI)
            }
            try PrivateFiles.write(ConfigurationGenerator.caddy(sites: validated, sockets: sockets, paths: paths, httpsPort: httpsPort,
                                                               httpPort: httpPort, inheritedListeners: listeningSockets != nil), to: paths.caddyConfig)
            let environment = ["PHP_INI_SCAN_DIR": paths.configuration.appendingPathComponent("empty-ini").path,
                               "XDG_DATA_HOME": paths.storage.path,
                               "XDG_CONFIG_HOME": paths.configuration.path]
            for (runtime, poolPaths) in pools {
                try await validate(ProcessRequest(executable: URL(fileURLWithPath: runtime.fpmPath),
                    arguments: ["-c", poolPaths.phpINI.path, "-y", poolPaths.fpmConfig.path, "-t"], directory: paths.root, environment: environment))
            }
            try checkStart()
            try await validate(ProcessRequest(executable: URL(fileURLWithPath: caddy.path),
                                              arguments: ["validate", "--config", paths.caddyConfig.path], directory: paths.root, environment: environment,
                                              listeningSockets: listeningSockets))
            let caBundle = try phpTrust.prepare(paths: paths, directory: paths.configuration)
            if let caBundle {
                let ini = ConfigurationGenerator.developmentINI + (try PHPConfigurationPolicy.trustINI(caBundle))
                for (_, poolPaths) in pools { try PrivateFiles.write(Data(ini.utf8), to: poolPaths.phpINI) }
            }
            try checkStart()
            for (runtime, poolPaths) in pools {
                let id = try await processes.start(ProcessRequest(executable: URL(fileURLWithPath: runtime.fpmPath),
                    arguments: ["-c", poolPaths.phpINI.path, "-y", poolPaths.fpmConfig.path, "-F"], directory: paths.root, environment: environment),
                    log: poolPaths.logs.appendingPathComponent("fpm.log"))
                fpmIDs.append(id)
                try await recordProcess(id, runtimeID: "PHP \(runtime.version)", paths: paths, signal: SIGQUIT)
                try checkStart()
                try await waitForSocket(poolPaths.socket, processID: id)
                try await fpmProbe.check(socket: poolPaths.socket)
                activeSockets.append(poolPaths.socket)
            }
            try checkStart()
            caddyID = try await processes.start(ProcessRequest(executable: URL(fileURLWithPath: caddy.path),
                                                              arguments: ["run", "--config", paths.caddyConfig.path], directory: paths.root, environment: environment,
                                                              listeningSockets: listeningSockets),
                                                log: paths.logs.appendingPathComponent("caddy.log"))
            if let caddyID { try await recordProcess(caddyID, runtimeID: "Caddy \(caddy.version)", paths: paths, signal: SIGTERM) }
            try checkStart()
            try await waitForTLS(sites: validated, paths: paths, port: httpsPort)
            try await verifyListeners(paths: paths, httpsPort: httpsPort, httpPort: httpPort,
                                      requireExclusiveOwnership: listeningSockets == nil)
            try checkStart()
            certificate = .issued
            state = .running
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self else { return }
                    await self.checkHealth()
                }
            }
        } catch {
            await stopOwned()
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    public func stop() async {
        stopRequested = true
        while operation {
            await Task.detached { try? await Task.sleep(for: .milliseconds(25)) }.value
        }
        operation = true
        defer { operation = false }
        monitor?.cancel()
        monitor = nil
        await stopOwned()
        state = .stopped
    }

    public func requestStop() {
        stopRequested = true
    }

    private func checkStart() throws {
        try Task.checkCancellation()
        if stopRequested { throw CancellationError() }
    }

    private func validate(_ request: ProcessRequest) async throws {
        let result = try await commands.run(request, timeout: .seconds(15))
        guard result.status == 0 else { throw JerdError.process("Configuration validation failed: \(result.diagnosticOutput)") }
    }

    private func waitForSocket(_ socket: URL, processID: UUID) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            try checkStart()
            guard await processes.isRunning(processID) else { throw JerdError.process("PHP-FPM exited before its socket was ready. See fpm.log.") }
            var info = stat()
            if lstat(socket.path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw JerdError.process("PHP-FPM did not create its socket. See fpm.log.")
    }

    private func waitForTLS(sites: [Site], paths: EnginePaths, port: UInt16) async throws {
        // Force 127.0.0.1 with curl --resolve so readiness works before hosts cache updates
        // and in isolated tests that never write /etc/hosts. Never use curl -k.
        for site in sites {
            let deadline = ContinuousClock.now + .seconds(20)
            var detail = "No certificate is available."
            var ready = false
            while ContinuousClock.now < deadline {
                try checkStart()
                guard await servicesAreRunning() else {
                    throw JerdError.process("A runtime exited during startup. See the run logs.")
                }
                if FileManager.default.fileExists(atPath: paths.rootCertificate.path) {
                    let result = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                        arguments: ["--noproxy", "*", "--silent", "--show-error", "--fail", "--max-time", "2",
                                    "--cacert", paths.rootCertificate.path, "--resolve", "\(site.hostname):\(port):127.0.0.1",
                                    "https://\(site.hostname):\(port)\(ConfigurationGenerator.healthPath)"], directory: paths.root), timeout: .seconds(4))
                    if result.status == 0, result.output == ConfigurationGenerator.healthResponse {
                        ready = true
                        break
                    }
                    detail = result.diagnosticOutput
                }
                try await Task.sleep(for: .milliseconds(150))
            }
            guard ready else { throw JerdError.process("TLS readiness failed: \(detail)") }
        }
    }

    private func verifyListeners(paths: EnginePaths, httpsPort: UInt16, httpPort: UInt16,
                                 requireExclusiveOwnership: Bool) async throws {
        guard let caddyID, let caddyPID = await processes.processIdentifier(caddyID) else { throw JerdError.process("Caddy exited before listener checks.") }
        let ports = LocalServicePorts(directory: paths.root, commands: commands)
        try await ports.verify(processID: caddyPID, ports: [httpsPort, httpPort],
                               requireExclusiveOwnership: requireExclusiveOwnership)
        for id in fpmIDs {
            guard let pid = await processes.processIdentifier(id) else { throw JerdError.process("PHP-FPM exited before listener checks.") }
            try await ports.verify(processID: pid, ports: [], rejectUDP: false)
        }
    }

    private func checkHealth() async {
        guard state == .running, !operation else { return }
        operation = true
        defer { operation = false }
        let alive = await servicesAreRunning()
        guard state == .running, !stopRequested else { return }
        if !alive {
            monitor?.cancel()
            state = .failed("An owned runtime exited. The environment was stopped. See the run logs.")
            await stopOwned()
        }
    }

    private func servicesAreRunning() async -> Bool {
        guard let caddyID, !fpmIDs.isEmpty, await processes.isRunning(caddyID) else { return false }
        for id in fpmIDs { if await !processes.isRunning(id) { return false } }
        return true
    }

    private func stopOwned() async {
        let caddyID = self.caddyID
        let fpmIDs = self.fpmIDs
        let activePaths = self.activePaths
        let ownsSocketDirectory = self.ownsSocketDirectory
        self.caddyID = nil
        self.fpmIDs.removeAll()
        self.activePaths = nil
        self.ownsSocketDirectory = false
        activeSockets.removeAll()
        if let caddyID { await processes.stop(caddyID, gracefulSignal: SIGTERM) }
        for id in fpmIDs { await processes.stop(id, gracefulSignal: SIGQUIT) }
        for (id, file) in recoveryFiles {
            if (try? PreviousProcessRun.read(file).isStale) == true { try? FileManager.default.removeItem(at: file) }
            recoveryFiles[id] = nil
        }
        if let lock = recoveryLock { _ = flock(lock, LOCK_UN); close(lock); recoveryLock = nil }
        if ownsSocketDirectory, let paths = activePaths {
            try? FileManager.default.removeItem(at: paths.socketDirectory)
        }
    }

    private func recordProcess(_ id: UUID, runtimeID: String, paths: EnginePaths, signal: Int32) async throws {
        guard let pid = await processes.processIdentifier(id) else { return }
        let file = paths.root.appendingPathComponent("processes/\(id.uuidString).json")
        try PreviousProcessRun.record(pid, runtimeID: runtimeID, at: file, signal: signal)
        recoveryFiles[id] = file
    }
}
