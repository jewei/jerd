/// The connection settings of one running instance, for a Laravel `.env` file.
public struct DatabaseConnection: Equatable, Sendable {
    public let engine: DatabaseEngine
    public let port: UInt16
    public let password: String

    public init(engine: DatabaseEngine, port: UInt16, password: String) {
        self.engine = engine
        self.port = port
        self.password = password
    }

    public var username: String { engine.username }
    public var database: String { engine.database }

    /// The Laravel environment lines, each ending with a newline.
    public var environment: String {
        if engine == .redis {
            return "REDIS_HOST=127.0.0.1\nREDIS_PORT=\(port)\nREDIS_USERNAME=default\nREDIS_PASSWORD=\(password)\n"
        }
        let connection = engine == .mysql ? "mysql" : "pgsql"
        return "DB_CONNECTION=\(connection)\nDB_HOST=127.0.0.1\nDB_PORT=\(port)\nDB_DATABASE=\(database)\n"
            + "DB_USERNAME=\(username)\nDB_PASSWORD=\(password)\n"
    }
}
