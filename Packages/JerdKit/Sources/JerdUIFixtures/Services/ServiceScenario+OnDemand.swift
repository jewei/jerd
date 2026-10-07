import JerdDatabases
import JerdRuntimes
import JerdServiceKit
import JerdUI

/// The scenarios of an app that installs its database runtimes on demand.
extension ServiceScenario {
    static let offlineMessage =
        "Jerd cannot reach the download server. Check the network connection, then try again."
    static let diskFullMessage =
        "There is not enough free disk space to install this runtime. Free some space, then try again."

    /// The databases of an on-demand scenario, or nil for the other scenarios.
    func onDemandDatabases() -> InMemoryDatabases? {
        switch self {
        case .databasesOnDemand, .dashboardDatabasesOnDemand, .databasesInstallFailed, .databaseEditorInstall,
            .databaseEditorInstalling, .databaseEditorInstallFailed, .databasesInstalling:
            // Redis is embedded, so the first launch installed it.
            return InMemoryDatabases(configuration: DatabaseConfiguration(runtimes: [SampleServices.redis]))
        case .databaseRuntimeInstalling:
            return InMemoryDatabases(
                configuration: DatabaseConfiguration(
                    runtimes: [SampleServices.mysql, SampleServices.redis], services: [SampleServices.studio]),
                states: [SampleServices.studioID: .running(pid: 4101)], started: [SampleServices.studioID])
        default:
            return nil
        }
    }

    /// The offers and the install answer, before the launch reads them.
    func configureOnDemand(_ databases: InMemoryDatabases) async {
        guard onDemandDatabases() != nil else { return }
        let behavior: InstallBehavior =
            switch self {
            case .databasesInstalling:
                .suspend(RuntimeInstallProgress("Downloading MySQL 8.4.11… 70.6 MB of 168 MB", 0.42))
            case .databaseRuntimeInstalling:
                .suspend(RuntimeInstallProgress("Downloading PostgreSQL 18.6… 51.5 MB of 122.5 MB", 0.42))
            case .databaseEditorInstalling:
                .suspend(RuntimeInstallProgress("Downloading PostgreSQL 18.6… 75 MB of 122.5 MB", 0.61))
            case .databasesInstallFailed: .fail(Self.offlineMessage)
            case .databaseEditorInstallFailed: .fail(Self.diskFullMessage)
            default: .succeed
            }
        await databases.configure {
            $0.offers = SampleServices.offers
            $0.installBehavior = behavior
        }
    }

    /// Runs the steps of an on-demand scenario. Returns false for the other scenarios.
    @MainActor
    func prepareOnDemand(_ state: AppState) async -> Bool {
        let model = state.databases
        switch self {
        case .databasesInstalling, .databaseRuntimeInstalling:
            model.requestRuntimeInstall(self == .databasesInstalling ? .mysql : .postgresql)
            model.confirmRuntimeInstall()
        case .databasesInstallFailed:
            model.requestRuntimeInstall(.mysql)
            await model.confirmRuntimeInstall()?.value
        case .databaseEditorInstall:
            model.beginAdd(.mysql)
            await waitForPort(model)
        case .databaseEditorInstalling, .databaseEditorInstallFailed:
            model.beginAdd(self == .databaseEditorInstalling ? .postgresql : .mysql)
            await waitForPort(model)
            let task = model.saveEditor()
            if self == .databaseEditorInstallFailed { await task?.value }
        default:
            return onDemandDatabases() != nil
        }
        return true
    }

    /// True when an on-demand scenario shows its state; nil for the other scenarios.
    @MainActor
    func isOnDemandReady(_ state: AppState) -> Bool? {
        let model = state.databases
        switch self {
        case .databasesInstalling, .databaseRuntimeInstalling, .databaseEditorInstalling:
            return model.runtimeInstallation?.progress != nil
        case .databasesInstallFailed: return model.runtimeNotice != nil
        case .databaseEditorInstall: return model.editor?.portText.isEmpty == false
        case .databaseEditorInstallFailed: return model.editorOperation.failureMessage != nil
        case .databasesOnDemand, .dashboardDatabasesOnDemand: return !model.runtimeOffers.isEmpty
        default: return nil
        }
    }
}
