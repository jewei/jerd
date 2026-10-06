import Foundation
import JerdFoundation

/// The files of one instance folder: the shared layout plus the engine files.
package struct DatabaseInstanceFiles: Hashable, Sendable {
    package let layout: DatabaseInstanceLayout

    package init(layout: DatabaseInstanceLayout) { self.layout = layout }

    package var root: URL { layout.root }
    package var data: URL { layout.dataDirectory }
    /// MySQL client options for the `jerd` account over TCP (contains the password).
    package var clientOptions: URL { layout.file(named: "client.cnf") }
    /// The PostgreSQL password file (contains the password).
    package var pgpass: URL { layout.file(named: "pgpass") }
    /// The Redis configuration (contains the password).
    package var redisConfiguration: URL { layout.file(named: "redis.conf") }
    /// The MySQL first-start SQL. Deleted when the setup readiness check ends.
    package var bootstrapSQL: URL { layout.file(named: "bootstrap.sql") }
    /// The MySQL first-start client options for `root` over the socket. Deleted when the setup
    /// readiness check ends.
    package var bootstrapOptions: URL { layout.file(named: "bootstrap.cnf") }
    /// The PostgreSQL `initdb` password file. Deleted after `initdb`.
    package var initPassword: URL { layout.file(named: "init-password") }
    /// The PID file that `mysqld` and `redis-server` write.
    package var serverPID: URL { layout.file(named: "server.pid") }
}
