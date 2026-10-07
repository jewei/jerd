import Foundation
import JerdProcess

/// Redis 8: `redis.conf` with loopback binding, protected mode, `requirepass`, and append-only
/// persistence. Clients get the password through `REDISCLI_AUTH`, never as an argument (it is
/// visible to the same user with `ps -E`).
package struct RedisDefinition: DatabaseEngineDefinition {
    package let runtime: DatabaseRuntime
    package let service: DatabaseService
    package let files: DatabaseInstanceFiles

    package init(runtime: DatabaseRuntime, service: DatabaseService, files: DatabaseInstanceFiles) {
        self.runtime = runtime
        self.service = service
        self.files = files
    }

    package var healthCheck: (command: [String], reply: String) { (["PING"], "PONG") }

    package func serverRequest(sockets: URL) -> ProcessRequest {
        request("redis-server", [files.redisConfiguration.path])
    }

    /// Redis needs no initializer: the data folder is created with mode 0700.
    package func initializerRequest() -> ProcessRequest? { nil }

    package func configuration(_ credentials: DatabaseCredentials, sockets: URL) -> EngineFile {
        EngineFile(
            url: files.redisConfiguration,
            contents: """
                bind 127.0.0.1
                protected-mode yes
                port \(service.port)
                daemonize no
                requirepass \(credentials.password)
                dir \(EngineFile.quoted(files.data.path))
                logfile ""
                pidfile \(EngineFile.quoted(files.serverPID.path))
                appendonly yes
                appendfsync everysec
                save 900 1

                """)
    }

    package func clientRequest(_ command: [String], credentials: DatabaseCredentials) -> ProcessRequest {
        request(
            "redis-cli",
            ["-h", "127.0.0.1", "-p", String(service.port), "--user", "default", "--no-auth-warning", "--raw"]
                + command, environment: ["REDISCLI_AUTH": credentials.password])
    }
}
