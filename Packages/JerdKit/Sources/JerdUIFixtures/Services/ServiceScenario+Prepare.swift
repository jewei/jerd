import JerdDatabases
import JerdUI

extension ServiceScenario {
    /// Launches the state and runs the extra steps of the scenario.
    @MainActor
    public func prepare(_ fixture: AppFixture) async {
        let state = fixture.state
        await configurePorts(fixture.services)
        await configureOnDemand(fixture.services.databases)
        await configureStorageOnDemand(fixture.services.storage)
        await configureMailOnDemand(fixture.services.mail)
        await state.launch()
        if await prepareMailOnDemand(state) { return }
        if await prepareStorageOnDemand(state) { return }
        if await prepareOnDemand(state) { return }
        if await prepareDatabaseScenario(state) { return }
        if await prepareStorageScenario(state) { return }
        if await prepareMailScenario(state) { return }
        if self == .advancedCommandLineTools {
            await state.commandLineTools.load()
            await state.commandLineTools.install()?.value
        }
    }

    /// True when the state shows what the scenario promises.
    @MainActor
    public func isReady(_ fixture: AppFixture) -> Bool {
        let state = fixture.state
        guard state.isLaunched else { return false }
        if let ready = isMailOnDemandReady(state) { return ready }
        if let ready = isStorageOnDemandReady(state) { return ready }
        if let ready = isOnDemandReady(state) { return ready }
        switch self {
        case .databaseEditor: return state.databases.editor?.portText.isEmpty == false
        case .databaseStarting: return !state.databases.busyServices.isEmpty
        case .databaseRuntimeMissing: return state.databases.operation.failureMessage != nil
        case .databaseCancelledSave: return state.databases.cancelledSaveMessage != nil
        case .databaseQuitting, .mailQuitting: return state.shutdown.message == ShutdownPhase.storage.message
        case .databasesLoadFailed: return state.databases.loadState.failureMessage != nil
        case .retainedDatabases: return !state.databases.retained.isEmpty
        case .mail: return state.mail.testResult != nil
        case .advancedCommandLineTools: return !state.commandLineTools.report.isEmpty
        default: return true
        }
    }

    /// Sets the behavior that the scenario needs before the launch reads the services.
    private func configurePorts(_ ports: InMemoryServicePorts) async {
        switch self {
        case .databaseStarting:
            await ports.databases.configure { $0.startBehavior = .suspend }
        case .databaseRuntimeMissing:
            await ports.databases.configure {
                $0.failure = "Reporting could not be removed because its data folder is in use by another app."
            }
        case .databaseCancelledSave:
            let gate = FixtureGate()
            await ports.databases.configure { $0.gate = gate }
        case .databaseQuitting, .mailQuitting:
            await ports.storage.configure { $0.stopBehavior = .suspend }
        case .databasesLoadFailed:
            await ports.databases.configure {
                $0.loadFailure = "databases.json line 4: The data could not be read."
            }
        case .databasesSetupFailed:
            await ports.databases.configure {
                $0.setupFailure = "The bundled PostgreSQL receipt does not match its pin."
            }
        case .storageSetupFailed:
            await ports.storage.configure { $0.setupFailure = "The app has no bundled storage runtimes." }
        case .mailSetupFailed:
            await ports.mail.configure { $0.setupFailure = "The app has no bundled mail runtimes." }
        default:
            break
        }
    }

    @MainActor
    func waitForPort(_ model: DatabasesModel) async {
        for _ in 0..<1_000 where model.editor?.portText.isEmpty != false {
            await Task.yield()
        }
    }
}
