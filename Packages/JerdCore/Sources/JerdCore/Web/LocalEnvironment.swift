import Foundation
import Darwin

public struct HTTPSSetup: Identifiable, Sendable {
    public var id: UUID { request.installationID }
    public let sites: [Site]
    public let request: SystemRegistrationRequest
    public var fingerprint: String { InstallationCertificate.fingerprint(request.certificateDER) }
}

public protocol TrustProbing: Sendable {
    func check(hostname: String) async throws
}

/// Uses the normal macOS trust store and hostname resolution. No custom CA or TLS override.
public final class SystemTrustProbe: NSObject, TrustProbing, URLSessionTaskDelegate, Sendable {
    public override init() {}
    public func check(hostname: String) async throws {
        let host = try Hostname.validate(hostname)
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
            throw JerdError.unavailable("The hostname does not resolve yet. Retry Start after macOS updates its host cache.")
        }
        defer { freeaddrinfo(first) }
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let value = current {
            let address = value.pointee
            guard address.ai_family == AF_INET, let pointer = address.ai_addr,
                  pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1, { $0.pointee.sin_addr.s_addr == inet_addr("127.0.0.1") }) else {
                throw JerdError.unavailable("The hostname must resolve only to 127.0.0.1.")
            }
            current = address.ai_next
        }
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://\(host)\(ConfigurationGenerator.healthPath)")!
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              String(data: data, encoding: .utf8) == ConfigurationGenerator.healthResponse else {
            throw JerdError.unavailable("The system HTTPS check did not receive Jerd's response.")
        }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) async -> URLRequest? { nil }
}

/// Coordinates all enabled sites. The helper never receives project paths or runs project code.
public actor LocalEnvironment {
    private let directory: URL
    private let system: any SystemIntegrating
    private let engine: any EngineServing
    private let probe: any TrustProbing
    private let commands: any CommandRunning
    private var sockets: ListeningSockets?
    private var activeSiteIDs: Set<UUID> = []
    private var operation = false
    private var monitor: Task<Void, Never>?
    public private(set) var state: EnvironmentState = .stopped

    public func snapshot() -> (state: EnvironmentState, siteIDs: Set<UUID>) { (state, activeSiteIDs) }

    public init(directory: URL, system: any SystemIntegrating, engine: any EngineServing = ServingEngine(),
                probe: any TrustProbing = SystemTrustProbe(), commands: any CommandRunning = LocalCommandRunner()) {
        self.directory = directory; self.system = system; self.engine = engine; self.probe = probe; self.commands = commands
    }

    public func prepare(sites: [Site], caddy: CaddyRuntime) async throws -> HTTPSSetup {
        guard !operation else { throw JerdError.invalid("An environment operation is in progress.") }
        operation = true
        defer { operation = false }
        let hostnames = try Hostname.validatedSet(sites.map(\.hostname))
        let identity = try installationID()
        let paths = makePaths(identity: identity)
        if !FileManager.default.fileExists(atPath: paths.rootCertificate.path) {
            guard activeSiteIDs.isEmpty else { throw JerdError.unavailable("Stop the environment before preparing a missing CA.") }
            try PrivateFiles.directory(paths.configuration)
            try PrivateFiles.directory(paths.storage)
            let name = "Jerd Local CA \(identity.uuidString)"
            let config: [String: Any] = ["admin": ["disabled": true],
                "storage": ["module": "file_system", "root": paths.storage.path],
                "apps": ["pki": ["certificate_authorities": ["jerd": ["name": name, "root_common_name": name, "install_trust": false]]]]]
            let file = paths.configuration.appendingPathComponent("prepare-ca.json")
            try PrivateFiles.write(JSONSerialization.data(withJSONObject: config), to: file)
            let result = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: caddy.path),
                arguments: ["validate", "--config", file.path], directory: directory,
                environment: ["XDG_DATA_HOME": paths.storage.path, "XDG_CONFIG_HOME": paths.configuration.path]), timeout: .seconds(15))
            guard result.status == 0 else { throw JerdError.process("Cannot prepare the local CA: \(result.output)") }
        }
        let der = try InstallationCertificate.decodePEM(Data(contentsOf: paths.rootCertificate))
        _ = try InstallationCertificate.validate(der, installationID: identity)
        return HTTPSSetup(sites: sites, request: SystemRegistrationRequest(installationID: identity, hostnames: hostnames,
            certificateDER: der, trustPolicy: .serverTLS))
    }

    public func apply(_ setup: HTTPSSetup) async throws {
        await stop()
        guard !operation else { throw JerdError.invalid("An environment operation is in progress.") }
        operation = true
        defer { operation = false }
        try await requireStandardPortsAvailable()
        try await system.configure(setup.request)
    }

    public func start(site: Site, runtime: DevelopmentRuntime, caddy: CaddyRuntime) async throws {
        try await start(sites: [SiteRuntime(site: site, runtime: runtime)], caddy: caddy)
    }

    public func start(sites: [SiteRuntime], caddy: CaddyRuntime) async throws {
        guard !operation, activeSiteIDs.isEmpty else { throw JerdError.invalid("Stop the environment before starting it again.") }
        operation = true
        state = .starting
        defer { operation = false }
        do {
            guard !sites.isEmpty, sites.allSatisfy({ $0.site.isEnabled }) else { throw JerdError.invalid("Enable the sites before starting them.") }
            let hostnames = try Hostname.validatedSet(sites.map { $0.site.hostname })
            let identity = try installationID()
            let paths = makePaths(identity: identity)
            let status = try await system.status()
            guard status.installationID == identity, Set(hostnames).isSubset(of: Set(status.hostnames)),
                  status.hostsConfigured, status.trustConfigured, status.trustPolicy == .serverTLS else {
                throw JerdError.unavailable("Select Enable HTTPS to approve setup for all enabled sites.")
            }
            let der = try InstallationCertificate.decodePEM(Data(contentsOf: paths.rootCertificate))
            guard status.certificateSHA256 == InstallationCertificate.fingerprint(der) else {
                throw JerdError.unavailable("The local CA does not match the approved system setup.")
            }
            try await requireStandardPortsAvailable()
            sockets = try await system.acquireListeners()
            try await engine.start(sites: sites, caddy: caddy, paths: paths,
                                   httpsPort: 443, httpPort: 80, listeningSockets: sockets)
            for hostname in hostnames { try await probe.check(hostname: hostname) }
            guard await engine.state == .running else { throw JerdError.process("The environment stopped during the HTTPS check.") }
            activeSiteIDs = Set(sites.map { $0.site.id })
            state = .running
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled, let self else { return }
                    await self.checkHealth()
                }
            }
        } catch {
            await cleanup()
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    public func stop() async {
        await engine.requestStop()
        while operation {
            await Task.detached { try? await Task.sleep(for: .milliseconds(30)) }.value
        }
        operation = true
        defer { operation = false }
        await cleanup()
        state = .stopped
    }

    public func removeSetup() async throws {
        await stop()
        guard !operation else { throw JerdError.invalid("An environment operation is in progress.") }
        operation = true
        defer { operation = false }
        try await system.removeSetup()
        state = .setupRequired
    }

    public func removeHostname(_ hostname: String) async throws {
        await stop()
        guard !operation else { throw JerdError.invalid("An environment operation is in progress.") }
        operation = true
        defer { operation = false }
        let status = try await system.status()
        guard status.hostnames.contains(hostname) else { return }
        let remaining = status.hostnames.filter { $0 != hostname }
        if remaining.isEmpty { try await system.removeSetup() }
        else {
            guard let identity = status.installationID, let der = status.certificateDER else {
                throw JerdError.unavailable("The approved certificate record is missing.")
            }
            try await requireStandardPortsAvailable()
            try await system.configure(SystemRegistrationRequest(installationID: identity, hostnames: remaining,
                certificateDER: der, trustPolicy: status.trustPolicy))
        }
    }

    private func installationID() throws -> UUID {
        try PrivateFiles.directory(directory)
        let url = directory.appendingPathComponent("installation-id")
        if FileManager.default.fileExists(atPath: url.path) {
            guard let id = UUID(uuidString: try String(contentsOf: url, encoding: .utf8)) else {
                throw JerdError.corruptConfiguration("The installation identity is invalid. It was preserved.")
            }
            return id
        }
        let id = UUID()
        try PrivateFiles.write(Data(id.uuidString.utf8), to: url)
        return id
    }

    private func makePaths(identity: UUID) -> EnginePaths {
        EnginePaths(root: directory, socketDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("jerd-\(UUID().uuidString.prefix(12))"), installationID: identity)
    }

    private func requireStandardPortsAvailable() async throws {
        let ports = LocalServicePorts(directory: directory, commands: commands)
        try await ports.requireExclusive(80)
        try await ports.requireExclusive(443)
    }

    private func checkHealth() async {
        guard !operation, !activeSiteIDs.isEmpty else { return }
        let health = await engine.state
        guard !operation, !activeSiteIDs.isEmpty else { return }
        if health != .running {
            operation = true
            await cleanup()
            state = health
            operation = false
        }
    }

    private func cleanup() async {
        monitor?.cancel(); monitor = nil
        await engine.stop()
        sockets?.close(); sockets = nil
        await system.releaseListeners()
        activeSiteIDs.removeAll()
    }
}
