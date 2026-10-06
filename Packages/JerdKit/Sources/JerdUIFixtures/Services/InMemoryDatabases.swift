import Foundation
import JerdDatabases
import JerdFoundation
import JerdServiceKit
import JerdUI

/// Database services in memory. Remove moves a service to the retained list, like the live
/// manager keeps its data folder.
public actor InMemoryDatabases: DatabasesPort {
    public var configuration: DatabaseConfiguration
    public var states: [UUID: ServiceState]
    /// Services whose first start created data.
    public var started: Set<UUID>
    public var retained: [RetainedDatabase]
    public var loadFailure: String?
    /// The reason of a failed bundled runtime setup that `runtimeSetupFailure()` reports.
    public var setupFailure: String?
    public var startBehavior = ServiceBehavior.succeed
    public var stopBehavior = ServiceBehavior.succeed
    /// When set, registry changes throw this message.
    public var failure: String?
    public var suggestion: UInt16 = 3307
    /// When set, add, edit, and restore wait here before they change anything.
    public var gate: FixtureGate?
    /// When set, the connection read waits here.
    public var connectionGate: FixtureGate?
    public private(set) var calls: [String] = []

    public init(
        configuration: DatabaseConfiguration = DatabaseConfiguration(), states: [UUID: ServiceState] = [:],
        started: Set<UUID> = [], retained: [RetainedDatabase] = []
    ) {
        self.configuration = configuration
        self.states = states
        self.started = started
        self.retained = retained
    }

    public func configure(_ change: @Sendable (isolated InMemoryDatabases) -> Void) {
        change(self)
    }

    public func load() async throws -> DatabaseSnapshot {
        calls.append("load")
        if let loadFailure { throw JerdError.corrupt(loadFailure) }
        return await snapshot()
    }

    public func runtimeSetupFailure() async -> String? {
        setupFailure
    }

    public func snapshot() async -> DatabaseSnapshot {
        DatabaseSnapshot(configuration: configuration, states: states)
    }

    public func files(for id: UUID) async -> ServiceFiles {
        SampleServices.files("databases/instances/\(id.uuidString)", hasData: started.contains(id))
    }

    public func suggestedPort(for engine: DatabaseEngine) async throws -> UInt16 { suggestion }

    public func add(name: String, runtimeID: String, port: UInt16) async throws -> DatabaseService {
        await gate?.pass()
        try record("add \(name) \(port)")
        let service = DatabaseService(name: name, runtimeID: runtimeID, port: port)
        configuration.services.append(service)
        return service
    }

    public func edit(_ service: DatabaseService) async throws {
        await gate?.pass()
        try record("edit \(service.name) \(service.port)")
        guard let index = configuration.services.firstIndex(where: { $0.id == service.id }) else { return }
        configuration.services[index] = service
    }

    public func remove(_ id: UUID) async throws {
        try record("remove \(id.uuidString)")
        guard let service = configuration.service(id) else { return }
        configuration.services.removeAll { $0.id == id }
        states[id] = nil
        if started.contains(id) {
            retained.append(
                RetainedDatabase(
                    id: id, name: service.name, runtime: try? configuration.runtime(for: service), port: service.port,
                    directory: URL(fileURLWithPath: "/tmp/\(id.uuidString)"), bytes: 1_024, problem: nil))
        }
    }

    public func start(_ id: UUID) async throws {
        calls.append("start \(id.uuidString)")
        switch startBehavior {
        case .succeed, .stuck:
            states[id] = .running(pid: 4100)
            started.insert(id)
        case .fail(let reason):
            states[id] = .failed(reason: reason)
            throw JerdError.processFailed(reason)
        case .suspend:
            try await ServiceBehavior.waitForCancellation()
        }
    }

    public func stop(_ id: UUID) async throws {
        calls.append("stop \(id.uuidString)")
        do {
            states[id] = try await ServiceStop.apply(stopBehavior, to: states[id] ?? .stopped)
        } catch let error as StuckError {
            states[id] = error.state
            throw error
        }
    }

    public func stopAll() async throws {
        calls.append("stop all")
        for (id, state) in states where state.processID != nil {
            do {
                states[id] = try await ServiceStop.apply(stopBehavior, to: state)
            } catch let error as StuckError {
                states[id] = error.state
                throw error
            }
        }
    }

    public func connection(for id: UUID) async throws -> DatabaseConnection {
        await connectionGate?.pass()
        guard let service = configuration.service(id), started.contains(id) else {
            throw JerdError.unavailable("Start the service once to create its credentials.")
        }
        let engine = try configuration.runtime(for: service).engine
        return DatabaseConnection(engine: engine, port: service.port, password: "sample-password-\(service.port)")
    }

    public func retainedDatabases() async throws -> [RetainedDatabase] {
        try record("inspect retained")
        return retained
    }

    public func restoreRegistration(_ id: UUID, name: String, port: UInt16) async throws -> DatabaseService {
        await gate?.pass()
        try record("restore \(name) \(port)")
        guard let database = retained.first(where: { $0.id == id }), let runtime = database.runtime else {
            throw JerdError.invalid("The retained folder cannot be restored.")
        }
        let service = DatabaseService(id: id, name: name, runtimeID: runtime.id, port: port)
        configuration.services.append(service)
        retained.removeAll { $0.id == id }
        started.insert(id)
        return service
    }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw JerdError.unavailable(failure) }
    }
}
