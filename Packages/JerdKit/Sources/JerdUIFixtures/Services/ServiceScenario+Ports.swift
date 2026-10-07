import Foundation
import JerdDatabases
import JerdMail
import JerdServiceKit
import JerdStorage
import JerdUI

extension ServiceScenario {
    /// The in-memory services of the scenario.
    func ports() -> InMemoryServicePorts {
        let base = InMemoryServicePorts(variant)
        return InMemoryServicePorts(
            databases: databases(base.databases), storage: storage(base.storage), mail: mail(base.mail),
            commandLineTools: InMemoryCommandLineTools(state: .outdatedLauncher))
    }

    private var variant: SampleFeatures.Variant {
        switch self {
        case .databasesEmpty, .databasesNoRuntimes, .storageEmpty: .empty
        case .databasesLong: .long
        case .databaseFailed: .busy
        default: .populated
        }
    }

    private func databases(_ base: InMemoryDatabases) -> InMemoryDatabases {
        if let onDemand = onDemandDatabases() { return onDemand }
        switch self {
        case .databasesNoRuntimes:
            return InMemoryDatabases()
        case .databasesSetupFailed:
            return InMemoryDatabases(configuration: DatabaseConfiguration(runtimes: [SampleServices.mysql]))
        case .databaseStopped, .databaseStarting:
            return InMemoryDatabases(
                configuration: SampleServices.databases(.populated), states: SampleServices.databaseStates(.populated),
                started: [SampleServices.studioID, SampleServices.cacheID])
        case .databaseFailed:
            // The failed service has a log, so the banner offers Open Log.
            return InMemoryDatabases(
                configuration: SampleServices.databases(.busy), states: SampleServices.databaseStates(.busy),
                started: [SampleServices.reportingID])
        case .databaseStuck:
            var states = SampleServices.databaseStates(.populated)
            states[SampleServices.cacheID] = .stuck(
                pid: 4102, reason: "Redis did not stop within 30 seconds.")
            return InMemoryDatabases(
                configuration: SampleServices.databases(.populated), states: states,
                started: [SampleServices.studioID, SampleServices.cacheID])
        case .databaseRuntimeMissing:
            let configuration = SampleServices.databases(.populated)
            return InMemoryDatabases(
                configuration: DatabaseConfiguration(
                    runtimes: configuration.runtimes.filter { $0.engine != .postgresql },
                    services: configuration.services),
                states: SampleServices.databaseStates(.populated),
                started: [SampleServices.studioID, SampleServices.cacheID, SampleServices.reportingID])
        default:
            return base
        }
    }

    private func storage(_ base: InMemoryStorage) -> InMemoryStorage {
        switch self {
        case .storageNoRuntime, .storageSetupFailed:
            return InMemoryStorage()
        case .storageEmpty, .addBucket, .addBucketInvalid:
            return InMemoryStorage(settings: StorageSettings(runtime: SampleServices.storageRuntime))
        case .storageStuck:
            return InMemoryStorage(
                settings: StorageSettings(runtime: SampleServices.storageRuntime, buckets: SampleServices.buckets),
                state: .stuck(pid: 4401, reason: "RustFS did not stop within 30 seconds."), hasData: true)
        case .storageFailed:
            return InMemoryStorage(
                settings: StorageSettings(runtime: SampleServices.storageRuntime, buckets: SampleServices.buckets),
                state: .failed(reason: SampleServices.storageFailure),
                hasData: true)
        default:
            return base
        }
    }

    private func mail(_ base: InMemoryMail) -> InMemoryMail {
        switch self {
        case .mailStopped:
            return InMemoryMail(settings: MailSettings(runtime: SampleServices.mailRuntime), hasData: true)
        case .mailStuck:
            return InMemoryMail(
                settings: MailSettings(runtime: SampleServices.mailRuntime),
                state: .stuck(pid: 4301, reason: "Mailpit did not stop within 15 seconds."), hasData: true)
        case .mailNoRuntime, .mailSetupFailed:
            return InMemoryMail()
        default:
            return base
        }
    }
}
