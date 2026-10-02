import Foundation
import Security

public enum DatabaseEngine: String, Codable, CaseIterable, Sendable {
    case mysql, postgresql, redis
    public var title: String {
        switch self { case .mysql: "MySQL"; case .postgresql: "PostgreSQL"; case .redis: "Redis" }
    }
    public var defaultPort: UInt16 {
        switch self { case .mysql: 3306; case .postgresql: 5432; case .redis: 6379 }
    }
    public var serverName: String {
        switch self { case .mysql: "mysqld"; case .postgresql: "postgres"; case .redis: "redis-server" }
    }
    public var clientName: String {
        switch self { case .mysql: "mysql"; case .postgresql: "psql"; case .redis: "redis-cli" }
    }
    public var username: String { self == .redis ? "default" : "jerd" }
    public var database: String {
        switch self { case .mysql: "jerd"; case .postgresql: "postgres"; case .redis: "0" }
    }
}

public struct DatabaseRuntime: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let engine: DatabaseEngine
    public let version: String
    public let path: String
    public init(id: String, engine: DatabaseEngine, version: String, path: String) {
        self.id = id; self.engine = engine; self.version = version; self.path = path
    }
    public func executable(_ name: String) -> URL {
        URL(fileURLWithPath: path).appendingPathComponent("bin").appendingPathComponent(name)
    }
}

public struct DatabaseService: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let runtimeID: String
    public var port: UInt16
    public init(id: UUID = UUID(), name: String, runtimeID: String, port: UInt16) {
        self.id = id; self.name = name; self.runtimeID = runtimeID; self.port = port
    }
}

public struct RetainedDatabase: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let runtime: DatabaseRuntime?
    public let port: UInt16?
    public let directory: URL
    public let bytes: Int64?
    public let problem: String?
    public var canRestore: Bool { problem == nil && runtime != nil }
}

public struct DatabaseConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var runtimes: [DatabaseRuntime] = []
    public var services: [DatabaseService] = []
    public init() {}
    public func runtime(for service: DatabaseService) throws -> DatabaseRuntime {
        guard let runtime = runtimes.first(where: { $0.id == service.runtimeID }) else {
            throw JerdError.unavailable("The selected database runtime is unavailable.")
        }
        return runtime
    }
    public func validate() throws {
        guard schemaVersion == 1, runtimes.count <= 100, services.count <= 100,
              Set(runtimes.map(\.id)).count == runtimes.count,
              Set(services.map(\.id)).count == services.count,
              Set(services.map(\.port)).count == services.count else {
            throw JerdError.corruptConfiguration("Database settings contain an unsupported version or duplicate records or ports.")
        }
        for runtime in runtimes {
            guard Self.safeIdentifier(runtime.id), Self.safeIdentifier(runtime.version),
                  runtime.path.hasPrefix("/"), !runtime.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw JerdError.invalid("The database runtime record is invalid.")
            }
        }
        for service in services {
            guard !service.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  service.name.count <= 80,
                  !service.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains), service.port > 1023 else {
                throw JerdError.invalid("Use a service name of 1 to 80 characters and a port from 1024 to 65535.")
            }
            _ = try runtime(for: service)
        }
    }
    public func validateForSave() throws {
        try validate()
        guard Set(services.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }).count == services.count else {
            throw JerdError.invalid("Each database service needs a unique name.")
        }
    }
    static func safeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value != "." && value != ".." && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46
        }
    }
}

public enum DatabaseState: Equatable, Sendable {
    case stopped, starting, running, stopping, failed(String)
    public var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "Ready"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }
    public var isBusy: Bool { self == .starting || self == .stopping }
}

public struct DatabaseStatus: Equatable, Sendable {
    public var state: DatabaseState
    public var processID: Int32?
    public init(state: DatabaseState = .stopped, processID: Int32? = nil) {
        self.state = state; self.processID = processID
    }
}

public struct DatabaseCredentials: Codable, Sendable {
    public let password: String
    public init() throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw JerdError.unavailable("Cannot create database credentials.")
        }
        password = bytes.map { String(format: "%02x", $0) }.joined()
    }
    public func validate() throws {
        guard password.utf8.count == 64, password.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw JerdError.corruptConfiguration("The database credential file is invalid. It was preserved.")
        }
    }
}

public struct DatabasePaths: Sendable {
    public let root: URL
    public var data: URL { root.appendingPathComponent("data") }
    public var credentials: URL { root.appendingPathComponent("credentials.json") }
    public var identity: URL { root.appendingPathComponent("runtime.json") }
    public var initialized: URL { root.appendingPathComponent("initialized.json") }
    public var log: URL { root.appendingPathComponent("server.log") }
    public var clientOptions: URL { root.appendingPathComponent("client.cnf") }
    public var pgpass: URL { root.appendingPathComponent("pgpass") }
    public var redisConfig: URL { root.appendingPathComponent("redis.conf") }
    public init(directory: URL, serviceID: UUID) {
        root = directory.appendingPathComponent("instances").appendingPathComponent(serviceID.uuidString)
    }
}
