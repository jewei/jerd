import Foundation
import JerdProcess

/// PostgreSQL 18: `initdb` with SCRAM authentication and a password file, `pgpass` for clients,
/// and `SIGINT` (fast shutdown) to stop.
package struct PostgresDefinition: DatabaseEngineDefinition {
    package let runtime: DatabaseRuntime
    package let service: DatabaseService
    package let files: DatabaseInstanceFiles

    package init(runtime: DatabaseRuntime, service: DatabaseService, files: DatabaseInstanceFiles) {
        self.runtime = runtime
        self.service = service
        self.files = files
    }

    package var healthCheck: (command: [String], reply: String) { (["SELECT 42"], "42") }

    package func serverRequest(sockets: URL) -> ProcessRequest {
        request(
            "postgres",
            [
                "-D", files.data.path, "-h", "127.0.0.1", "-p", String(service.port), "-k", sockets.path, "-c",
                "unix_socket_permissions=0700", "-c", "logging_collector=off",
            ])
    }

    package func initializerRequest() -> ProcessRequest? {
        request(
            "initdb",
            [
                "-D", files.data.path, "-U", "jerd", "--auth-local=scram-sha-256", "--auth-host=scram-sha-256",
                "--encoding=UTF8", "--locale=C", "--pwfile=\(files.initPassword.path)", "--no-instructions",
            ])
    }

    /// `init-password`: the password and a newline.
    package func initializerFiles(_ credentials: DatabaseCredentials) -> [EngineFile] {
        [EngineFile(url: files.initPassword, contents: credentials.password + "\n")]
    }

    package func configuration(_ credentials: DatabaseCredentials, sockets: URL) -> EngineFile {
        EngineFile(url: files.pgpass, contents: "127.0.0.1:\(service.port):*:jerd:\(credentials.password)\n")
    }

    package func clientRequest(_ command: [String], credentials: DatabaseCredentials) -> ProcessRequest {
        request(
            "psql",
            [
                "--no-psqlrc", "--no-password", "--host=127.0.0.1", "--port=\(service.port)", "--username=jerd",
                "--dbname=postgres", "--tuples-only", "--no-align", "--set=ON_ERROR_STOP=1", "--command",
                command.joined(separator: ";"),
            ], environment: ["PGPASSFILE": files.pgpass.path, "PGCONNECT_TIMEOUT": "1"])
    }
}
