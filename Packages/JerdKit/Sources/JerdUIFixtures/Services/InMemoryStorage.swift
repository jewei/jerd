import JerdFoundation
import JerdServiceKit
import JerdStorage
import JerdUI

/// RustFS and its buckets in memory. A saved bucket starts storage when needed, like the live
/// manager, and becomes complete at once unless `bucketFailure` is set.
public actor InMemoryStorage: StoragePort {
    public var settings: StorageSettings
    public var state: ServiceState
    public var listed: Set<String>
    public var hasData: Bool
    public var loadFailure: String?
    /// The reason of a failed bundled runtime setup that `runtimeSetupFailure()` reports.
    public var setupFailure: String?
    public var startBehavior = ServiceBehavior.succeed
    public var stopBehavior = ServiceBehavior.succeed
    /// When set, Save and Retry throw this message and keep the bucket unfinished.
    public var bucketFailure: String?
    public var failure: String?
    /// When set, Add Bucket and the port change wait here before they change anything.
    public var gate: FixtureGate?
    public private(set) var calls: [String] = []

    public init(
        settings: StorageSettings = StorageSettings(), state: ServiceState = .stopped, listed: Set<String> = [],
        hasData: Bool = false
    ) {
        self.settings = settings
        self.state = state
        self.listed = listed
        self.hasData = hasData
    }

    public func configure(_ change: @Sendable (isolated InMemoryStorage) -> Void) {
        change(self)
    }

    public func load() async throws -> StorageSnapshot {
        calls.append("load")
        if let loadFailure { throw JerdError.corrupt(loadFailure) }
        return await snapshot()
    }

    public func runtimeSetupFailure() async -> String? {
        setupFailure
    }

    public func snapshot() async -> StorageSnapshot {
        StorageSnapshot(settings: settings, state: state, availableBuckets: listed)
    }

    public func files() async -> ServiceFiles { SampleServices.files("storage", hasData: hasData) }

    public func start() async throws {
        calls.append("start")
        switch startBehavior {
        case .succeed, .stuck:
            state = .running(pid: 4401)
            hasData = true
            listed.formUnion(settings.buckets.filter(\.setupComplete).map(\.name))
        case .fail(let reason):
            state = .failed(reason: reason)
            throw JerdError.processFailed(reason)
        case .suspend:
            try await ServiceBehavior.waitForCancellation()
        }
    }

    public func stop() async throws {
        calls.append("stop")
        do {
            state = try await ServiceStop.apply(stopBehavior, to: state)
        } catch let error as StuckError {
            state = error.state
            throw error
        }
    }

    public func addBucket(name: String, publicRead: Bool) async throws {
        await gate?.pass()
        calls.append("add \(name) \(publicRead ? "public" : "private")")
        if settings.bucket(name) == nil {
            settings.buckets.append(StorageBucket(name: name, publicRead: publicRead))
        }
        try await finishBucket(name)
    }

    public func retryBucket(_ name: String) async throws {
        calls.append("retry \(name)")
        try await finishBucket(name)
    }

    public func refreshBuckets() async throws {
        calls.append("refresh buckets")
        if let failure { throw JerdError.unavailable(failure) }
    }

    public func credentials() async throws -> StorageCredentials {
        guard hasData else { throw JerdError.unavailable("Start storage once to create its credentials.") }
        return SampleServices.credentials
    }

    public func suggestedPorts() async throws -> StoragePorts {
        if let failure { throw JerdError.unavailable(failure) }
        return StoragePorts(api: 9010, console: 9011)
    }

    public func edit(ports: StoragePorts) async throws {
        await gate?.pass()
        calls.append("edit \(ports.api) \(ports.console)")
        if let failure { throw JerdError.unavailable(failure) }
        settings.ports = ports
    }

    private func finishBucket(_ name: String) async throws {
        if !state.isRunning { try await start() }
        if let bucketFailure { throw JerdError.unavailable(bucketFailure) }
        guard let index = settings.buckets.firstIndex(where: { $0.name == name }) else { return }
        settings.buckets[index].setupComplete = true
        listed.insert(name)
    }
}
