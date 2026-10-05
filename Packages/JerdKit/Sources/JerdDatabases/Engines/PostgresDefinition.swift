import Foundation
import JerdProcess

/// PostgreSQL 18: `initdb` with SCRAM authentication and a password file, `pgpass` for clients,
/// and `SIGINT` (fast shutdown) to stop.
public struct PostgresDefinition: DatabaseEngineDefinition {
    public let runtime: DatabaseRuntime
    public let service: DatabaseService
    public let files: DatabaseInstanceFiles

    public init(runtime: DatabaseRuntime, service: DatabaseService, files: DatabaseInstanceFiles) {
        self.runtime = runtime
        self.service = service
        self.files = files
    }

    public var healthCheck: (command: [String], reply: String) { (["SELECT 42"], "42") }

    public func serverRequest(sockets: URL) -> ProcessRequest {
        request(
            "postgres",
            [
                "-D", files.data.path, "-h", "127.0.0.1", "-p", String(service.port), "-k", sockets.path, "-c",
                "unix_socket_permissions=0700", "-c", "logging_collector=off",
            ])
    }

    public func initializerRequest() -> ProcessRequest? {
        request(
            "initdb",
            [
                "-D", files.data.path, "-U", "jerd", "--auth-local=scram-sha-256", "--auth-host=scram-sha-256",
                "--encoding=UTF8", "--locale=C", "--pwfile=\(files.initPassword.path)", "--no-instructions",
            ])
    }

    /// `init-password`: the password and a newline.
    public func initializerFiles(_ credentials: DatabaseCredentials) -> [EngineFile] {
        [EngineFile(url: files.initPassword, contents: credentials.password + "\n")]
    }

    public func configuration(_ credentials: DatabaseCredentials, sockets: URL) -> EngineFile {
        EngineFile(url: files.pgpass, contents: "127.0.0.1:\(service.port):*:jerd:\(credentials.password)\n")
    }

    public func clientRequest(_ command: [String], credentials: DatabaseCredentials) -> ProcessRequest {
        request(
            "psql",
            [
                "--no-psqlrc", "--no-password", "--host=127.0.0.1", "--port=\(service.port)", "--username=jerd",
                "--dbname=postgres", "--tuples-only", "--no-align", "--set=ON_ERROR_STOP=1", "--command",
                command.joined(separator: ";"),
            ], environment: ["PGPASSFILE": files.pgpass.path, "PGCONNECT_TIMEOUT": "1"])
    }
}
