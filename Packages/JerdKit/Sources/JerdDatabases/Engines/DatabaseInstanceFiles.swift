import Foundation
import JerdFoundation

/// The files of one instance folder: the shared layout plus the engine files.
public struct DatabaseInstanceFiles: Hashable, Sendable {
    public let layout: DatabaseInstanceLayout

    public init(layout: DatabaseInstanceLayout) { self.layout = layout }

    public var root: URL { layout.root }
    public var data: URL { layout.dataDirectory }
    /// MySQL client options for the `jerd` account over TCP (contains the password).
    public var clientOptions: URL { layout.file(named: "client.cnf") }
    /// The PostgreSQL password file (contains the password).
    public var pgpass: URL { layout.file(named: "pgpass") }
    /// The Redis configuration (contains the password).
    public var redisConfiguration: URL { layout.file(named: "redis.conf") }
    /// The MySQL first-start SQL. Deleted after the setup phase.
    public var bootstrapSQL: URL { layout.file(named: "bootstrap.sql") }
    /// The MySQL first-start client options for `root` over the socket. Deleted after the setup phase.
    public var bootstrapOptions: URL { layout.file(named: "bootstrap.cnf") }
    /// The PostgreSQL `initdb` password file. Deleted after `initdb`.
    public var initPassword: URL { layout.file(named: "init-password") }
    /// The PID file that `mysqld` and `redis-server` write.
    public var serverPID: URL { layout.file(named: "server.pid") }
}
