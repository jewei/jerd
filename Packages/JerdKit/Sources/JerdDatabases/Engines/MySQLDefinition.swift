import Foundation
import JerdProcess

/// MySQL 8.4: `mysqld --initialize-insecure`, then a socket-only bootstrap server that sets the
/// passwords and creates the `jerd` account and database, then the TCP server on 127.0.0.1.
package struct MySQLDefinition: DatabaseEngineDefinition {
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
        request("mysqld", serverArguments(sockets: sockets))
    }

    package func initializerRequest() -> ProcessRequest? {
        request(
            "mysqld",
            ["--no-defaults", "--initialize-insecure", "--basedir=\(runtime.path)", "--datadir=\(files.data.path)"])
    }

    package func configuration(_ credentials: DatabaseCredentials, sockets: URL) -> EngineFile {
        EngineFile(
            url: files.clientOptions,
            contents: """
                [client]
                user=jerd
                password=\(credentials.password)
                host=127.0.0.1
                port=\(service.port)
                protocol=tcp

                """)
    }

    package func clientRequest(_ command: [String], credentials: DatabaseCredentials) -> ProcessRequest {
        request("mysql", clientArguments(options: files.clientOptions, command) + ["jerd"])
    }

    /// The bootstrap server with `--skip-networking` and the bootstrap SQL as `--init-file`.
    package func setupPhase(_ credentials: DatabaseCredentials, sockets: URL) -> DatabaseSetupPhase? {
        let server = request(
            "mysqld",
            serverArguments(sockets: sockets) + ["--skip-networking", "--init-file=\(files.bootstrapSQL.path)"])
        let client = request("mysql", clientArguments(options: files.bootstrapOptions, healthCheck.command))
        return DatabaseSetupPhase(files: bootstrapFiles(credentials, sockets: sockets), server: server, client: client)
    }

    /// `bootstrap.sql` and `bootstrap.cnf` (root over the socket).
    package func bootstrapFiles(_ credentials: DatabaseCredentials, sockets: URL) -> [EngineFile] {
        let password = credentials.password
        let sql = """
            ALTER USER 'root'@'localhost' IDENTIFIED BY '\(password)';
            CREATE USER 'jerd'@'127.0.0.1' IDENTIFIED BY '\(password)';
            GRANT ALL PRIVILEGES ON *.* TO 'jerd'@'127.0.0.1' WITH GRANT OPTION;
            CREATE DATABASE jerd CHARACTER SET utf8mb4;

            """
        let options = """
            [client]
            user=root
            password=\(password)
            protocol=socket
            socket=\(EngineFile.quoted(socket(in: sockets).path))

            """
        return [
            EngineFile(url: files.bootstrapSQL, contents: sql),
            EngineFile(url: files.bootstrapOptions, contents: options),
        ]
    }

    private func socket(in sockets: URL) -> URL { sockets.appendingPathComponent("mysql.sock") }

    private func serverArguments(sockets: URL) -> [String] {
        [
            "--no-defaults", "--basedir=\(runtime.path)", "--datadir=\(files.data.path)", "--bind-address=127.0.0.1",
            "--port=\(service.port)", "--socket=\(socket(in: sockets).path)", "--pid-file=\(files.serverPID.path)",
            "--mysqlx=0", "--skip-log-bin", "--skip-name-resolve", "--persisted-globals-load=OFF", "--local-infile=0",
        ]
    }

    private func clientArguments(options: URL, _ command: [String]) -> [String] {
        [
            "--defaults-file=\(options.path)", "--no-login-paths", "--connect-timeout=1", "--batch",
            "--skip-column-names", "--execute", command.joined(separator: ";"),
        ]
    }
}
