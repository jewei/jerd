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
        await state.launch()
        if await prepareStorageOnDemand(state) { return }
        if await prepareOnDemand(state) { return }
        switch self {
        case .databaseEditor:
            state.databases.beginAdd(.postgresql)
            await waitForPort(state.databases)
        case .databaseEditorInvalid:
            state.databases.beginAdd(.mysql)
            state.databases.editor?.setName("Studio cache")
            state.databases.editor?.setPort("6379")
        case .databaseStarting:
            state.databases.start(SampleServices.reportingID)
        case .databaseCancelledSave:
            state.databases.beginEdit(SampleServices.reportingID)
            state.databases.saveEditor()
            state.databases.closeEditor()
        case .databaseQuitting, .mailQuitting:
            _ = state.requestTermination { _ in }
        case .databaseRuntimeMissing:
            state.databases.requestRemove(SampleServices.reportingID)
            await state.databases.confirmRemove()?.value
        case .retainedDatabases:
            state.databases.showRetained()
            await state.databases.inspectRetained()?.value
        case .restoreDatabase:
            state.databases.beginRestore(SampleServices.retained[0])
        case .addBucket:
            state.storage.beginAddBucket()
            state.storage.bucketDraft?.name = "studio-uploads"
        case .addBucketInvalid:
            state.storage.beginAddBucket()
            state.storage.bucketDraft = BucketDraft(name: "Studio_Uploads", publicRead: true)
        case .storagePorts:
            state.storage.editPorts()
        case .mail:
            await state.mail.sendTestEmail()?.value
        case .mailPorts:
            await state.mail.stop()?.value
            state.mail.editPorts()
            state.mail.portsDraft?.second = "1025"
        case .advancedCommandLineTools:
            await state.commandLineTools.load()
            await state.commandLineTools.install()?.value
        default:
            break
        }
    }

    /// True when the state shows what the scenario promises.
    @MainActor
    public func isReady(_ fixture: AppFixture) -> Bool {
        let state = fixture.state
        guard state.isLaunched else { return false }
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
