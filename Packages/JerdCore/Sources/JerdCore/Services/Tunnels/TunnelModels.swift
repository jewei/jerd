import Foundation

public struct TunnelRuntime: Codable, Equatable, Sendable {
    public let id: String
    public let version: String
    public let path: String
    public var executable: URL { URL(fileURLWithPath: path).appendingPathComponent("cloudflared") }
    public init(id: String, version: String, path: String) { self.id = id; self.version = version; self.path = path }
}

public struct TunnelRegistration: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var hostname: String
    public var siteID: UUID?
    public var originURL: String?
    public var startOnLaunch: Bool
    public var restartOnFailure: Bool
    public var metricsPort: UInt16
    public init(id: UUID = UUID(), name: String, hostname: String, siteID: UUID? = nil,
                originURL: String? = nil, startOnLaunch: Bool = false, restartOnFailure: Bool = true,
                metricsPort: UInt16 = 20241) {
        self.id = id; self.name = name; self.hostname = hostname; self.siteID = siteID; self.originURL = originURL
        self.startOnLaunch = startOnLaunch; self.restartOnFailure = restartOnFailure; self.metricsPort = metricsPort
    }
    public var publicURL: URL? { URL(string: "https://\(hostname)") }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains), metricsPort > 1023 else {
            throw JerdError.invalid("Enter a name of 1 to 100 characters and a metrics port above 1023.")
        }
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard hostname.count <= 253, labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }), !hostname.hasSuffix(".localhost"), hostname != "localhost", hostname != "127.0.0.1" else {
            throw JerdError.invalid("Enter a public hostname in lower case, such as preview.example.com. Do not include a scheme or path.")
        }
        if let originURL {
            guard siteID == nil, let url = URLComponents(string: originURL), ["http", "https"].contains(url.scheme),
                  ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host), url.user == nil, url.password == nil,
                  url.fragment == nil, url.port.map({ (1...65535).contains($0) }) ?? true else {
                throw JerdError.invalid("Use one registered site or a local HTTP or HTTPS address without credentials.")
            }
        }
    }
}

public struct TunnelConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var runtime: TunnelRuntime?
    public var tunnels: [TunnelRegistration]
    public init(runtime: TunnelRuntime? = nil, tunnels: [TunnelRegistration] = []) { self.runtime = runtime; self.tunnels = tunnels }
    public func validate() throws {
        guard schemaVersion == 1, tunnels.count <= 100, Set(tunnels.map(\.id)).count == tunnels.count,
              Set(tunnels.map(\.metricsPort)).count == tunnels.count else {
            throw JerdError.invalid("Tunnel settings have an unsupported format, duplicate records, or duplicate metrics ports.")
        }
        for tunnel in tunnels { try tunnel.validate() }
        if let runtime {
            guard DatabaseConfiguration.safeIdentifier(runtime.id), DatabaseConfiguration.safeIdentifier(runtime.version),
                  runtime.path.hasPrefix("/"), !runtime.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw JerdError.invalid("The cloudflared runtime record is invalid.")
            }
        }
    }
}

public enum TunnelState: Equatable, Sendable {
    case stopped, starting, connected, reconnecting, stopping, failed(String)
    public var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting…"
        case .stopping: "Stopping…"
        case .failed: "Needs attention"
        }
    }
}
public struct TunnelSnapshot: Equatable, Sendable {
    public let registration: TunnelRegistration
    public let state: TunnelState
    public let processID: Int32?
    public init(registration: TunnelRegistration, state: TunnelState, processID: Int32? = nil) {
        self.registration = registration; self.state = state; self.processID = processID
    }
}
public struct TunnelPaths: Sendable {
    public let root: URL
    public var home: URL { root.appendingPathComponent("home") }
    public var config: URL { root.appendingPathComponent("config.yml") }
    public var log: URL { root.appendingPathComponent("server.log") }
    public var activeRun: URL { root.appendingPathComponent("active-run.json") }
    public init(root: URL) { self.root = root }
}
