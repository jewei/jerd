import JerdDatabases
import JerdUI

extension ServiceScenario {
    /// Launches the state and runs the extra steps of the scenario.
    @MainActor
    public func prepare(_ fixture: AppFixture) async {
        let state = fixture.state
        await state.launch()
        switch self {
        case .databaseEditor:
            state.databases.beginAdd(.postgresql)
            await waitForPort(state.databases)
        case .databaseEditorInvalid:
            state.databases.beginAdd(.mysql)
            state.databases.editor?.setName("Studio cache")
            state.databases.editor?.setPort("6379")
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
        switch self {
        case .databaseEditor: return state.databases.editor?.portText.isEmpty == false
        case .retainedDatabases: return !state.databases.retained.isEmpty
        case .mail: return state.mail.testResult != nil
        case .advancedCommandLineTools: return !state.commandLineTools.report.isEmpty
        default: return true
        }
    }

    @MainActor
    private func waitForPort(_ model: DatabasesModel) async {
        for _ in 0..<1_000 where model.editor?.portText.isEmpty != false {
            await Task.yield()
        }
    }
}
