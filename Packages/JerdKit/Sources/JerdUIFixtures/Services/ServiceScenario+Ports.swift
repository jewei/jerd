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
        switch self {
        case .databasesNoRuntimes:
            return InMemoryDatabases()
        case .databaseStopped:
            return InMemoryDatabases(
                configuration: SampleServices.databases(.populated), states: SampleServices.databaseStates(.populated),
                started: [SampleServices.studioID, SampleServices.cacheID])
        case .databaseStuck:
            var states = SampleServices.databaseStates(.populated)
            states[SampleServices.cacheID] = .stuck(
                pid: 4102, reason: "Redis did not stop within 30 seconds.")
            return InMemoryDatabases(
                configuration: SampleServices.databases(.populated), states: states,
                started: [SampleServices.studioID, SampleServices.cacheID])
        default:
            return base
        }
    }

    private func storage(_ base: InMemoryStorage) -> InMemoryStorage {
        switch self {
        case .storageNoRuntime:
            return InMemoryStorage()
        case .storageEmpty, .addBucket, .addBucketInvalid:
            return InMemoryStorage(settings: StorageSettings(runtime: SampleServices.storageRuntime))
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
        case .mailNoRuntime:
            return InMemoryMail()
        default:
            return base
        }
    }
}
