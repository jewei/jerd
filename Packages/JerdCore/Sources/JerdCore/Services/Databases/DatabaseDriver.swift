import Foundation

/// Engine-specific arguments and private configuration. Password values never
/// appear in a process argument or a health-check result.
public enum DatabaseDriver {
    public static func server(runtime: DatabaseRuntime, service: DatabaseService, paths: DatabasePaths,
                              sockets: URL, bootstrap: Bool = false) -> ProcessRequest {
        var arguments: [String]
        switch runtime.engine {
        case .mysql:
            arguments = ["--no-defaults", "--basedir=\(runtime.path)", "--datadir=\(paths.data.path)",
                "--bind-address=127.0.0.1", "--port=\(service.port)", "--socket=\(sockets.appendingPathComponent("mysql.sock").path)",
                "--pid-file=\(paths.root.appendingPathComponent("server.pid").path)", "--mysqlx=0", "--skip-log-bin",
                "--skip-name-resolve", "--persisted-globals-load=OFF", "--local-infile=0"]
            if bootstrap {
                arguments += ["--skip-networking", "--init-file=\(paths.root.appendingPathComponent("bootstrap.sql").path)"]
            }
        case .postgresql:
            arguments = ["-D", paths.data.path, "-h", "127.0.0.1", "-p", String(service.port), "-k", sockets.path,
                         "-c", "unix_socket_permissions=0700", "-c", "logging_collector=off"]
        case .redis:
            arguments = [paths.redisConfig.path]
        }
        return ProcessRequest(executable: runtime.executable(runtime.engine.serverName), arguments: arguments, directory: paths.root)
    }

    public static func initialization(runtime: DatabaseRuntime, paths: DatabasePaths) -> ProcessRequest? {
        switch runtime.engine {
        case .mysql:
            ProcessRequest(executable: runtime.executable("mysqld"), arguments: ["--no-defaults", "--initialize-insecure",
                "--basedir=\(runtime.path)", "--datadir=\(paths.data.path)"], directory: paths.root)
        case .postgresql:
            ProcessRequest(executable: runtime.executable("initdb"), arguments: ["-D", paths.data.path, "-U", "jerd",
                "--auth-local=scram-sha-256", "--auth-host=scram-sha-256", "--encoding=UTF8", "--locale=C",
                "--pwfile=\(paths.root.appendingPathComponent("init-password").path)", "--no-instructions"], directory: paths.root)
        case .redis: nil
        }
    }

    public static func writeConfiguration(runtime: DatabaseRuntime, service: DatabaseService, paths: DatabasePaths,
                                          credentials: DatabaseCredentials, sockets: URL) throws {
        try credentials.validate()
        switch runtime.engine {
        case .mysql:
            let settings = """
            [client]
            user=jerd
            password=\(credentials.password)
            host=127.0.0.1
            port=\(service.port)
            protocol=tcp

            """
            try PrivateFiles.write(Data(settings.utf8), to: paths.clientOptions)
        case .postgresql:
            try PrivateFiles.write(Data("127.0.0.1:\(service.port):*:jerd:\(credentials.password)\n".utf8), to: paths.pgpass)
        case .redis:
            let settings = """
            bind 127.0.0.1
            protected-mode yes
            port \(service.port)
            daemonize no
            requirepass \(credentials.password)
            dir \(quote(paths.data.path))
            logfile ""
            pidfile \(quote(paths.root.appendingPathComponent("server.pid").path))
            appendonly yes
            appendfsync everysec
            save 900 1

            """
            try PrivateFiles.write(Data(settings.utf8), to: paths.redisConfig)
        }
    }

    static func writeBootstrap(paths: DatabasePaths, credentials: DatabaseCredentials, sockets: URL) throws {
        try credentials.validate()
        let password = credentials.password
        let sql = """
        ALTER USER 'root'@'localhost' IDENTIFIED BY '\(password)';
        CREATE USER 'jerd'@'127.0.0.1' IDENTIFIED BY '\(password)';
        GRANT ALL PRIVILEGES ON *.* TO 'jerd'@'127.0.0.1' WITH GRANT OPTION;
        CREATE DATABASE jerd CHARACTER SET utf8mb4;

        """
        try PrivateFiles.write(Data(sql.utf8), to: paths.root.appendingPathComponent("bootstrap.sql"))
        let options = """
        [client]
        user=root
        password=\(password)
        protocol=socket
        socket=\(quote(sockets.appendingPathComponent("mysql.sock").path))

        """
        try PrivateFiles.write(Data(options.utf8), to: paths.root.appendingPathComponent("bootstrap.cnf"))
    }

    public static func healthCheck(runtime: DatabaseRuntime, service: DatabaseService, paths: DatabasePaths,
                                   credentials: DatabaseCredentials, bootstrap: Bool = false) -> ProcessRequest {
        client(runtime: runtime, service: service, paths: paths, credentials: credentials,
               command: runtime.engine == .redis ? ["PING"] : ["SELECT 42"], bootstrap: bootstrap)
    }

    /// Used for service probes and the opt-in persistence test. Commands are
    /// passed directly to the database client, without a shell.
    public static func client(runtime: DatabaseRuntime, service: DatabaseService, paths: DatabasePaths,
                              credentials: DatabaseCredentials, command: [String], bootstrap: Bool = false) -> ProcessRequest {
        let arguments: [String]
        var environment: [String: String] = [:]
        switch runtime.engine {
        case .mysql:
            let options = bootstrap ? paths.root.appendingPathComponent("bootstrap.cnf") : paths.clientOptions
            arguments = ["--defaults-file=\(options.path)", "--no-login-paths", "--connect-timeout=1", "--batch", "--skip-column-names",
                         "--execute", command.joined(separator: ";" )] + (bootstrap ? [] : ["jerd"])
        case .postgresql:
            arguments = ["--no-psqlrc", "--no-password", "--host=127.0.0.1", "--port=\(service.port)", "--username=jerd",
                         "--dbname=postgres", "--tuples-only", "--no-align", "--set=ON_ERROR_STOP=1", "--command", command.joined(separator: ";")]
            environment = ["PGPASSFILE": paths.pgpass.path, "PGCONNECT_TIMEOUT": "1"]
        case .redis:
            arguments = ["-h", "127.0.0.1", "-p", String(service.port), "--user", "default", "--no-auth-warning", "--raw"] + command
            environment = ["REDISCLI_AUTH": credentials.password]
        }
        return ProcessRequest(executable: runtime.executable(runtime.engine.clientName), arguments: arguments,
                              directory: paths.root, environment: environment)
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
