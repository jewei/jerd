import Foundation
import JerdDatabases
import JerdMail
import JerdServiceKit
import JerdStorage
import JerdUI

/// Database, storage, and mail data for the fixtures. Paths use a sample home folder.
public enum SampleServices {
    static let root = "/Users/developer/Library/Application Support/Jerd"

    public static let mysql = DatabaseRuntime(
        id: "mysql-8.4.3", engine: .mysql, version: "8.4.3", path: "\(root)/database-runtimes/mysql-8.4.3")
    public static let postgres = DatabaseRuntime(
        id: "postgresql-17.2", engine: .postgresql, version: "17.2", path: "\(root)/database-runtimes/postgresql-17.2")
    public static let redis = DatabaseRuntime(
        id: "redis-7.4.1", engine: .redis, version: "7.4.1", path: "\(root)/database-runtimes/redis-7.4.1")

    public static let studioID = uuid("6F1B2C3D-0000-4000-8000-000000000001")
    public static let cacheID = uuid("6F1B2C3D-0000-4000-8000-000000000002")
    public static let reportingID = uuid("6F1B2C3D-0000-4000-8000-000000000003")
    public static let retainedID = uuid("6F1B2C3D-0000-4000-8000-000000000004")

    public static let studio = DatabaseService(
        id: studioID, name: "Studio development", runtimeID: mysql.id, port: 3306)
    public static let cache = DatabaseService(id: cacheID, name: "Studio cache", runtimeID: redis.id, port: 6379)
    public static let reporting = DatabaseService(
        id: reportingID, name: "Reporting", runtimeID: postgres.id, port: 5432)

    public static func databases(_ variant: SampleFeatures.Variant) -> DatabaseConfiguration {
        let runtimes = [mysql, postgres, redis]
        switch variant {
        case .empty: return DatabaseConfiguration(runtimes: runtimes)
        case .populated, .busy: return DatabaseConfiguration(runtimes: runtimes, services: [studio, cache, reporting])
        case .long:
            return DatabaseConfiguration(runtimes: runtimes, services: [studio, cache, reporting] + longServices)
        }
    }

    public static func databaseStates(_ variant: SampleFeatures.Variant) -> [UUID: ServiceState] {
        switch variant {
        case .empty: [:]
        case .populated, .long: [studioID: .running(pid: 4101), cacheID: .running(pid: 4102)]
        case .busy:
            [
                studioID: .starting,
                reportingID: .failed(reason: reportingFailure),
            ]
        }
    }

    static let longServices: [DatabaseService] = (1...9).map { index in
        DatabaseService(
            id: uuid("6F1B2C3D-0000-4000-8000-0000000001\(String(format: "%02d", index))"),
            name: index == 1
                ? "Reporting warehouse with a very long descriptive name for the quarterly exports"
                : "Replica \(index)",
            runtimeID: index.isMultiple(of: 2) ? postgres.id : mysql.id, port: UInt16(3306 + index * 10))
    }

    public static let retained: [RetainedDatabase] = [
        RetainedDatabase(
            id: retainedID, name: "Billing archive", runtime: postgres, port: 5433,
            directory: URL(fileURLWithPath: "\(root)/databases/instances/\(retainedID.uuidString)"),
            bytes: 48_234_496, problem: nil),
        RetainedDatabase(
            id: uuid("6F1B2C3D-0000-4000-8000-000000000005"), name: "Legacy search", runtime: nil, port: 3307,
            directory: URL(fileURLWithPath: "\(root)/databases/instances/6F1B2C3D-0000-4000-8000-000000000005"),
            bytes: nil, problem: "Its MySQL 5.7 runtime is not installed. Install it to restore this folder."),
    ]

    public static let mailRuntime = MailRuntime(
        id: "mailpit-1.28.0", version: "1.28.0", path: "\(root)/mail-runtimes/1.28.0")
    public static let storageRuntime = StorageRuntime(
        id: "rustfs-1.0.0", version: "1.0.0", path: "\(root)/storage-runtimes/1.0.0")

    public static let buckets = [
        StorageBucket(name: "studio-uploads", publicRead: false, setupComplete: true),
        StorageBucket(name: "studio-public-assets", publicRead: true, setupComplete: true),
        StorageBucket(name: "reports-archive", publicRead: false, setupComplete: false),
    ]

    public static let credentials = StorageCredentials(
        accessKey: "JERD0123456789ABCDEF", secretKey: "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF")

    /// A failure as the service layer reports it: the message, then the end of the server log
    /// with absolute paths. The page shows the message, Open Log, and the last lines.
    public static let reportingFailure = """
        PostgreSQL exited before it was ready. 2026-10-06 22:13:01.402 UTC [4103] LOG:  starting PostgreSQL 17.6
        2026-10-06 22:13:01.405 UTC [4103] LOG:  listening on IPv4 address "127.0.0.1", port 5432
        2026-10-06 22:13:01.406 UTC [4103] FATAL:  could not create lock file \
        "\(root)/databases/instances/\(reportingID.uuidString)/data/postmaster.pid": Permission denied
        2026-10-06 22:13:01.407 UTC [4103] LOG:  database system is shut down
        """

    /// A RustFS start that failed, with the end of its log.
    public static let storageFailure = """
        RustFS exited before it was ready. [2026-10-06T22:13:01Z INFO  rustfs] Starting RustFS 1.0.0
        [2026-10-06T22:13:01Z INFO  rustfs::storage] Using data folder \(root)/storage/data
        [2026-10-06T22:13:01Z ERROR rustfs::storage] \(root)/storage/data/.rustfs.sys: disk is read-only
        [2026-10-06T22:13:01Z ERROR rustfs] Startup failed: storage is not writable
        """

    /// The files of a service folder under the sample data root.
    static func files(_ folder: String, data: String = "data", hasData: Bool) -> ServiceFiles {
        ServiceFiles(
            dataFolder: URL(fileURLWithPath: "\(root)/\(folder)/\(data)"),
            log: URL(fileURLWithPath: "\(root)/\(folder)/server.log"), hasDataFolder: hasData, hasLog: hasData)
    }

    private static func uuid(_ text: String) -> UUID {
        UUID(uuidString: text) ?? UUID()
    }
}
