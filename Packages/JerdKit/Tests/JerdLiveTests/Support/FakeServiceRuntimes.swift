import JerdDatabases
import JerdFoundation
import JerdMail
import JerdManifest
import JerdStorage

@testable import JerdLive

/// Bundled service runtimes without payloads: set records, a failure switch, and the requests.
actor FakeServiceRuntimes: ServiceRuntimeSource {
    static let mysql = DatabaseRuntime(id: "mysql-8.4", engine: .mysql, version: "8.4.1", path: "/runtimes/mysql")
    static let redis = DatabaseRuntime(id: "redis-8.8", engine: .redis, version: "8.8.3", path: "/runtimes/redis")
    static let mail = MailRuntime(id: "mailpit-1.31.3", version: "1.31.3", path: "/runtimes/mailpit")
    static let storage = StorageRuntime(id: "rustfs-1.0.0", version: "1.0.0", path: "/runtimes/rustfs")

    private(set) var databaseRequests: [Set<RuntimeKind>] = []
    private(set) var mailRequests = 0
    private(set) var storageRequests = 0
    let failure: JerdError?
    /// False for an app that installs RustFS on demand: it embeds no storage runtime.
    let embedsStorage: Bool
    /// False for an app that installs Mailpit on demand: it embeds no mail runtime.
    let embedsMail: Bool

    init(failure: JerdError? = nil, embedsStorage: Bool = true, embedsMail: Bool = true) {
        self.failure = failure
        self.embedsStorage = embedsStorage
        self.embedsMail = embedsMail
    }

    func databaseRuntimes(excluding: Set<RuntimeKind>) throws -> [DatabaseRuntime] {
        databaseRequests.append(excluding)
        if let failure { throw failure }
        return [Self.mysql, Self.redis].filter { !excluding.contains(BundledRuntimeMapping.kind(of: $0.engine)) }
    }

    func mailRuntime() throws -> MailRuntime? {
        mailRequests += 1
        if let failure { throw failure }
        return embedsMail ? Self.mail : nil
    }

    func storageRuntime() throws -> StorageRuntime? {
        storageRequests += 1
        if let failure { throw failure }
        return embedsStorage ? Self.storage : nil
    }
}
