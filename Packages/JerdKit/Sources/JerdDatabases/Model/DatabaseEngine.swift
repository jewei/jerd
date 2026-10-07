import Darwin

/// A database engine that Jerd manages. The raw values are saved in `services.json`.
public enum DatabaseEngine: String, Codable, CaseIterable, Sendable {
    case mysql
    case postgresql
    case redis

    /// The name shown to a user.
    public var title: String {
        switch self {
        case .mysql: "MySQL"
        case .postgresql: "PostgreSQL"
        case .redis: "Redis"
        }
    }

    /// The first port that a suggestion tries.
    public var defaultPort: UInt16 {
        switch self {
        case .mysql: 3_306
        case .postgresql: 5_432
        case .redis: 6_379
        }
    }

    /// The server executable in `<runtime>/bin`.
    public var serverName: String {
        switch self {
        case .mysql: "mysqld"
        case .postgresql: "postgres"
        case .redis: "redis-server"
        }
    }

    /// The client executable in `<runtime>/bin`.
    public var clientName: String {
        switch self {
        case .mysql: "mysql"
        case .postgresql: "psql"
        case .redis: "redis-cli"
        }
    }

    /// The account that applications use.
    public var username: String { self == .redis ? "default" : "jerd" }

    /// The database that applications use (the Redis database number for Redis).
    public var database: String {
        switch self {
        case .mysql: "jerd"
        case .postgresql: "postgres"
        case .redis: "0"
        }
    }

    /// The graceful stop signal: `SIGINT` is the PostgreSQL fast shutdown.
    public var stopSignal: Int32 { self == .postgresql ? SIGINT : SIGTERM }
}
