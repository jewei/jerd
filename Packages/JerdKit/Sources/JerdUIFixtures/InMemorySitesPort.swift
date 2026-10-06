import Foundation
import JerdFoundation
import JerdUI
import JerdWeb

/// Sites, the environment, and the HTTPS setup in memory, with the approval rule of the live
/// transaction: a start of hostnames that the setup does not cover waits for approval.
public actor InMemorySitesPort: SitesPort {
    public var configurationValue: AppConfiguration
    public var environmentValue: EnvironmentSnapshot
    public var setup: HTTPSSetupStatus
    /// When set, every change throws this message.
    public var failure: String?
    /// When set, reading the configuration throws this message.
    public var loadFailure: String?
    /// When true, a change waits until `requestStop()`, then ends with `CancellationError`.
    public var suspendsChanges = false
    /// When true, reading the configuration waits until `releaseLoad()`, for launch tests.
    public var holdsLoad = false
    private var heldLoads: [CheckedContinuation<Void, Never>] = []
    public var suggestions: [String: DocumentRootSuggestion] = [:]
    public var logsURL: URL?
    public private(set) var calls: [String] = []
    /// How often the environment was read, for polling tests.
    public private(set) var environmentReads = 0
    private var pending: [UUID: Set<UUID>] = [:]
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// A Stop that arrived before the suspended change began to wait, like the live stop epoch.
    private var stopRequested = false

    public init(
        configuration: AppConfiguration = SampleData.siteConfiguration,
        environment: EnvironmentSnapshot = EnvironmentSnapshot(state: .stopped, siteIDs: []),
        setup: HTTPSSetupStatus = SampleData.approvedSetup, loadFailure: String? = nil
    ) {
        self.loadFailure = loadFailure
        configurationValue = configuration
        environmentValue = environment
        self.setup = setup
    }

    public func configure(_ change: @Sendable (isolated InMemorySitesPort) -> Void) {
        change(self)
    }

    public func loadConfiguration() async throws -> AppConfiguration {
        calls.append("load")
        if holdsLoad {
            await withCheckedContinuation { heldLoads.append($0) }
        }
        if let loadFailure { throw JerdError.corrupt(loadFailure) }
        return configurationValue
    }

    /// Lets a held load finish.
    public func releaseLoad() {
        holdsLoad = false
        let held = heldLoads
        heldLoads = []
        for continuation in held { continuation.resume() }
    }

    public func environment() async -> EnvironmentSnapshot {
        environmentReads += 1
        return environmentValue
    }
    public func setupStatus() async throws -> HTTPSSetupStatus { setup }

    public func apply(_ change: SiteChange, startIfStopped: Bool) async throws -> SiteChangeOutcome {
        try await record("apply \(Self.describe(change))")
        switch change {
        case .save(let site, _):
            let index = configurationValue.sites.firstIndex { $0.id == site.id }
            let isNew = index == nil
            if let index {
                configurationValue.sites[index] = site
            } else {
                configurationValue.sites.append(site)
            }
            if startIfStopped, isNew, environmentValue.siteIDs.isEmpty { return try await serve([site.id]) }
        case .enabled(let id, let isEnabled):
            if let index = configurationValue.sites.firstIndex(where: { $0.id == id }) {
                configurationValue.sites[index].isEnabled = isEnabled
            }
        case .remove(let id):
            configurationValue.sites.removeAll { $0.id == id }
            environmentValue = EnvironmentSnapshot(
                state: environmentValue.state, siteIDs: environmentValue.siteIDs.subtracting([id]))
        default:
            break
        }
        return .committed(configurationValue)
    }

    public func run(_ siteIDs: Set<UUID>) async throws -> SiteChangeOutcome {
        try await record("run \(siteIDs.count)")
        return try await serve(siteIDs)
    }

    public func approve(_ approval: HTTPSApproval) async throws -> AppConfiguration {
        try await record("approve \(approval.hostnames.joined(separator: ","))")
        setup = HTTPSSetupStatus(
            hostnames: approval.hostnames, certificateSHA256: approval.fingerprint, hostsConfigured: true,
            trustConfigured: true, trustPolicy: .serverTLS)
        environmentValue = EnvironmentSnapshot(state: .running, siteIDs: pending[approval.id] ?? [])
        pending[approval.id] = nil
        return configurationValue
    }

    public func discard(_ approval: HTTPSApproval) async {
        calls.append("discard")
        pending[approval.id] = nil
    }

    public func requestStop() async {
        calls.append("request stop")
        stopRequested = waiting.isEmpty
        let resumed = waiting
        waiting = []
        for continuation in resumed { continuation.resume() }
    }

    public func stopEnvironment() async throws {
        try await record("stop environment")
        environmentValue = EnvironmentSnapshot(state: .stopped, siteIDs: [])
    }

    public func suggestDocumentRoot(projectPath: String) async throws -> DocumentRootSuggestion {
        calls.append("inspect \(projectPath)")
        return suggestions[projectPath] ?? DocumentRootSuggestion(path: projectPath, isLaravel: false)
    }

    public func environmentLogs() async -> URL? { logsURL }

    public func reconnectHelper() async throws {
        try await record("reconnect helper")
    }

    public func removeSystemSetup() async throws {
        try await record("remove system setup")
        setup = HTTPSSetupStatus()
        environmentValue = EnvironmentSnapshot(state: .setupRequired, siteIDs: [])
    }

    public func openLoginItems() async {
        calls.append("open login items")
    }

    /// Serves `ids`, or asks for approval when the setup does not cover their hostnames.
    private func serve(_ ids: Set<UUID>) async throws -> SiteChangeOutcome {
        let hostnames = configurationValue.sites.filter { ids.contains($0.id) }.map(\.hostname)
        guard ids.isEmpty || ApprovalPredicate.covers(setup, hostnames: hostnames) else {
            let approval = HTTPSApproval(
                hostnames: configurationValue.sites.map(\.hostname).sorted(), fingerprint: SampleData.caFingerprint)
            pending[approval.id] = ids
            return .needsApproval(approval)
        }
        environmentValue = EnvironmentSnapshot(state: ids.isEmpty ? .stopped : .running, siteIDs: ids)
        return .committed(configurationValue)
    }

    private func record(_ call: String) async throws {
        calls.append(call)
        if let failure { throw JerdError.unavailable(failure) }
        if suspendsChanges {
            if !stopRequested {
                await withCheckedContinuation { waiting.append($0) }
            }
            stopRequested = false
            throw CancellationError()
        }
    }

    private static func describe(_ change: SiteChange) -> String {
        switch change {
        case .save(let site, let confirmed): "save \(site.hostname) confirmed=\(confirmed)"
        case .enabled(let id, let isEnabled): "enabled \(id.uuidString.prefix(8)) \(isEnabled)"
        case .remove(let id): "remove \(id.uuidString.prefix(8))"
        default: "other"
        }
    }
}
