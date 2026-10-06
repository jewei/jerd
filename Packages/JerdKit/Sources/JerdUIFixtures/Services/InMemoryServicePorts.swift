import JerdMail
import JerdServiceKit
import JerdStorage
import JerdUI

/// The in-memory database, storage, mail, and command-line tools ports, filled for one
/// dashboard variant.
public struct InMemoryServicePorts: Sendable {
    public let databases: InMemoryDatabases
    public let storage: InMemoryStorage
    public let mail: InMemoryMail
    public let commandLineTools: InMemoryCommandLineTools

    public init(
        databases: InMemoryDatabases, storage: InMemoryStorage, mail: InMemoryMail,
        commandLineTools: InMemoryCommandLineTools = InMemoryCommandLineTools()
    ) {
        self.databases = databases
        self.storage = storage
        self.mail = mail
        self.commandLineTools = commandLineTools
    }

    /// The services of a dashboard variant: none, three, some at work, or many with long names.
    public init(_ variant: SampleFeatures.Variant) {
        let running = variant == .populated || variant == .long
        let states = SampleServices.databaseStates(variant)
        databases = InMemoryDatabases(
            configuration: SampleServices.databases(variant), states: states,
            started: Set(states.keys).union(variant == .empty ? [] : [SampleServices.reportingID]),
            retained: SampleServices.retained)
        let buckets = variant == .empty ? [] : SampleServices.buckets
        storage = InMemoryStorage(
            settings: StorageSettings(runtime: SampleServices.storageRuntime, buckets: buckets),
            state: running ? .running(pid: 4401) : (variant == .busy ? .starting : .stopped),
            listed: running ? ["studio-uploads", "studio-public-assets"] : [], hasData: variant != .empty)
        mail = InMemoryMail(
            settings: MailSettings(runtime: SampleServices.mailRuntime),
            state: running ? .running(pid: 4301) : .stopped,
            hasData: variant != .empty)
        commandLineTools = InMemoryCommandLineTools()
    }

    /// The ports for `AppDependencies`.
    public var ports: ServicePorts {
        ServicePorts(databases: databases, storage: storage, mail: mail, commandLineTools: commandLineTools)
    }
}
