import Foundation

public enum JerdError: Error, LocalizedError, Equatable, Sendable {
    case invalid(String)
    case unavailable(String)
    case corruptConfiguration(String)
    case process(String)
    case approvalInterrupted(String)
    case partialChange(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .unavailable(let message),
             .corruptConfiguration(let message), .process(let message), .approvalInterrupted(let message),
             .partialChange(let message): message
        }
    }
}

public enum PHPSelection: Codable, Hashable, Sendable {
    case followDefault
    case pinned(UUID)
}

public struct Site: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var projectPath: String
    public var documentRoot: String
    public var hostname: String
    public var phpSelection: PHPSelection
    public var isEnabled: Bool

    public init(id: UUID = UUID(), displayName: String, projectPath: String,
                documentRoot: String, hostname: String,
                phpSelection: PHPSelection = .followDefault, isEnabled: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.projectPath = projectPath
        self.documentRoot = documentRoot
        self.hostname = hostname
        self.phpSelection = phpSelection
        self.isEnabled = isEnabled
    }
}

public enum CPUArchitecture: String, Codable, Sendable {
    case arm64, x86_64
    public static var current: Self {
        #if arch(arm64)
        .arm64
        #else
        .x86_64
        #endif
    }
}

public struct DevelopmentRuntime: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public let cliPath: String
    public let fpmPath: String
    public let version: String
    public let architectures: [CPUArchitecture]
    public let cliExtensions: [String]
    public let fpmExtensions: [String]
    public let inspectedAt: Date

    public init(id: UUID = UUID(), cliPath: String, fpmPath: String, version: String,
                architectures: [CPUArchitecture], cliExtensions: [String],
                fpmExtensions: [String], inspectedAt: Date = Date()) {
        self.id = id
        self.cliPath = cliPath
        self.fpmPath = fpmPath
        self.version = version
        self.architectures = architectures
        self.cliExtensions = cliExtensions
        self.fpmExtensions = fpmExtensions
        self.inspectedAt = inspectedAt
    }
}

public struct CaddyRuntime: Codable, Equatable, Sendable {
    public let path: String
    public let version: String
    public let architectures: [CPUArchitecture]
}

public struct SiteRuntime: Sendable {
    public let site: Site
    public let runtime: DevelopmentRuntime
    public init(site: Site, runtime: DevelopmentRuntime) { self.site = site; self.runtime = runtime }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var schemaVersion = currentVersion
    public var sites: [Site] = []
    public var runtimes: [DevelopmentRuntime] = []
    public var defaultRuntimeID: UUID?
    public var caddy: CaddyRuntime?
    public init() {}

    public func runtime(for site: Site) throws -> DevelopmentRuntime {
        let selected: UUID?
        switch site.phpSelection {
        case .followDefault: selected = defaultRuntimeID
        case .pinned(let id): selected = id
        }
        guard let selected, let runtime = runtimes.first(where: { $0.id == selected }) else {
            throw JerdError.unavailable("The selected PHP runtime is unavailable. Select an installed runtime.")
        }
        return runtime
    }

    public mutating func removeRuntime(_ id: UUID) throws {
        guard defaultRuntimeID != id,
              !sites.contains(where: { $0.phpSelection == .pinned(id) }) else {
            throw JerdError.invalid("Reassign the default and all pinned sites before removing this runtime.")
        }
        runtimes.removeAll { $0.id == id }
    }
}

public enum EnvironmentState: Equatable, Sendable {
    case setupRequired, starting, running, stopped, failed(String)
}

// Engine issuance does not establish system trust. LocalEnvironment checks that separately.
public enum CertificateState: Equatable, Sendable { case notIssued, issued }
public enum TrustState: Equatable, Sendable { case setupRequired }
