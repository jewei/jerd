import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdDatabases

@Suite struct EngineDefinitionTests {
    static let password = String(repeating: "ab", count: 32)
    static let credentials = DatabaseCredentials(password: password)
    static let instance = DataLayout(root: URL(fileURLWithPath: "/data/Jerd ü")).databases.instance(UUID())
    static let root = instance.root
    static let sockets = URL(fileURLWithPath: "/tmp/jerd-db-ABCDEF12-3", isDirectory: true)
    static let files = DatabaseInstanceFiles(layout: instance)
    static let service = DatabaseService(name: "Local", runtimeID: "r", port: 13_306)

    static func runtime(_ engine: DatabaseEngine) -> DatabaseRuntime {
        DatabaseRuntime(id: "r", engine: engine, version: "1.0", path: "/runtimes/\(engine.rawValue)")
    }

    static let mysql = MySQLDefinition(runtime: runtime(.mysql), service: service, files: files)
    static let postgres = PostgresDefinition(runtime: runtime(.postgresql), service: service, files: files)
    static let redis = RedisDefinition(runtime: runtime(.redis), service: service, files: files)

    @Test func mysqlRunsWithoutDefaultsOnLoopbackOnly() throws {
        let server = Self.mysql.serverRequest(sockets: Self.sockets)
        #expect(server.executable.path == "/runtimes/mysql/bin/mysqld")
        #expect(server.workingDirectory == Self.root)
        #expect(server.environment.isEmpty)
        #expect(
            server.arguments == [
                "--no-defaults", "--basedir=/runtimes/mysql", "--datadir=\(Self.root.path)/data",
                "--bind-address=127.0.0.1", "--port=13306", "--socket=/tmp/jerd-db-ABCDEF12-3/mysql.sock",
                "--pid-file=\(Self.root.path)/server.pid", "--mysqlx=0", "--skip-log-bin", "--skip-name-resolve",
                "--persisted-globals-load=OFF", "--local-infile=0",
            ])
        #expect(
            Self.mysql.initializerRequest()?.arguments == [
                "--no-defaults", "--initialize-insecure", "--basedir=/runtimes/mysql",
                "--datadir=\(Self.root.path)/data",
            ])
        let client = Self.mysql.clientRequest(["SELECT 42"], credentials: Self.credentials)
        #expect(client.executable.lastPathComponent == "mysql")
        #expect(
            client.arguments == [
                "--defaults-file=\(Self.root.path)/client.cnf", "--no-login-paths", "--connect-timeout=1", "--batch",
                "--skip-column-names", "--execute", "SELECT 42", "jerd",
            ])
        #expect(
            Self.mysql.configuration(Self.credentials, sockets: Self.sockets).contents
                == "[client]\nuser=jerd\npassword=\(Self.password)\nhost=127.0.0.1\nport=13306\nprotocol=tcp\n")
    }

    @Test func mysqlBootstrapIsSocketOnlyAndUsesRootOverTheSocket() throws {
        let phase = try #require(Self.mysql.setupPhase(Self.credentials, sockets: Self.sockets))
        #expect(
            phase.server.arguments.suffix(2) == ["--skip-networking", "--init-file=\(Self.root.path)/bootstrap.sql"])
        #expect(
            phase.client.arguments == [
                "--defaults-file=\(Self.root.path)/bootstrap.cnf", "--no-login-paths", "--connect-timeout=1",
                "--batch", "--skip-column-names", "--execute", "SELECT 42",
            ])
        let sql = try #require(phase.files.first { $0.url.lastPathComponent == "bootstrap.sql" })
        #expect(
            sql.contents
                == "ALTER USER 'root'@'localhost' IDENTIFIED BY '\(Self.password)';\n"
                + "CREATE USER 'jerd'@'127.0.0.1' IDENTIFIED BY '\(Self.password)';\n"
                + "GRANT ALL PRIVILEGES ON *.* TO 'jerd'@'127.0.0.1' WITH GRANT OPTION;\n"
                + "CREATE DATABASE jerd CHARACTER SET utf8mb4;\n")
        let options = try #require(phase.files.first { $0.url.lastPathComponent == "bootstrap.cnf" })
        #expect(
            options.contents
                == "[client]\nuser=root\npassword=\(Self.password)\nprotocol=socket\n"
                + "socket=\"/tmp/jerd-db-ABCDEF12-3/mysql.sock\"\n")
    }

    @Test func optionValuesEscapeBackslashesAndQuotes() {
        #expect(EngineFile.quoted(#"/a "b" \c"#) == #""/a \"b\" \\c""#)
    }

    @Test func postgresUsesSCRAMAndAPasswordFile() throws {
        #expect(
            Self.postgres.initializerRequest()?.arguments == [
                "-D", "\(Self.root.path)/data", "-U", "jerd", "--auth-local=scram-sha-256", "--auth-host=scram-sha-256",
                "--encoding=UTF8", "--locale=C", "--pwfile=\(Self.root.path)/init-password", "--no-instructions",
            ])
        #expect(
            Self.postgres.initializerFiles(Self.credentials) == [
                EngineFile(url: Self.root.appendingPathComponent("init-password"), contents: Self.password + "\n")
            ])
        #expect(
            Self.postgres.serverRequest(sockets: Self.sockets).arguments == [
                "-D", "\(Self.root.path)/data", "-h", "127.0.0.1", "-p", "13306", "-k", "/tmp/jerd-db-ABCDEF12-3", "-c",
                "unix_socket_permissions=0700", "-c", "logging_collector=off",
            ])
        #expect(
            Self.postgres.configuration(Self.credentials, sockets: Self.sockets).contents
                == "127.0.0.1:13306:*:jerd:\(Self.password)\n")
        let client = Self.postgres.clientRequest(["SELECT 1", "SELECT 2"], credentials: Self.credentials)
        #expect(client.arguments.last == "SELECT 1;SELECT 2")
        #expect(client.environment == ["PGPASSFILE": "\(Self.root.path)/pgpass", "PGCONNECT_TIMEOUT": "1"])
        #expect(Self.postgres.setupPhase(Self.credentials, sockets: Self.sockets) == nil)
    }

    @Test func redisUsesAProtectedAppendOnlyConfiguration() {
        #expect(Self.redis.serverRequest(sockets: Self.sockets).arguments == ["\(Self.root.path)/redis.conf"])
        #expect(Self.redis.initializerRequest() == nil)
        #expect(
            Self.redis.configuration(Self.credentials, sockets: Self.sockets).contents
                == "bind 127.0.0.1\nprotected-mode yes\nport 13306\ndaemonize no\nrequirepass \(Self.password)\n"
                + "dir \"\(Self.root.path)/data\"\nlogfile \"\"\npidfile \"\(Self.root.path)/server.pid\"\n"
                + "appendonly yes\nappendfsync everysec\nsave 900 1\n")
        let client = Self.redis.clientRequest(["PING"], credentials: Self.credentials)
        #expect(
            client.arguments == [
                "-h", "127.0.0.1", "-p", "13306", "--user", "default", "--no-auth-warning", "--raw", "PING",
            ])
        #expect(client.environment == ["REDISCLI_AUTH": Self.password])
        #expect(Self.redis.healthCheck.reply == "PONG")
    }

    @Test func passwordsNeverAppearInArguments() throws {
        let engines: [any DatabaseEngineDefinition] = [Self.mysql, Self.postgres, Self.redis]
        for engine in engines {
            var requests = [
                engine.serverRequest(sockets: Self.sockets),
                engine.clientRequest(engine.healthCheck.command, credentials: Self.credentials),
            ]
            if let initializer = engine.initializerRequest() { requests.append(initializer) }
            if let phase = engine.setupPhase(Self.credentials, sockets: Self.sockets) {
                requests += [phase.server, phase.client]
            }
            for request in requests { #expect(!request.arguments.joined().contains(Self.password)) }
        }
    }

    @Test(arguments: DatabaseEngine.allCases)
    func engineFilesArePrivate(_ engine: DatabaseEngine) throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let layout = DataLayout(root: directory.url).databases.instance(UUID())
        try OwnedDirectory.create(layout.root)
        let files = DatabaseInstanceFiles(layout: layout)
        let definition = DatabaseServiceDefinition.engine(
            runtime: Self.runtime(engine), service: Self.service, files: files)
        let file = definition.configuration(Self.credentials, sockets: Self.sockets)
        try file.write()
        #expect(mode(file.url) == 0o600)
        #expect(text(file.url) == file.contents)
    }
}
