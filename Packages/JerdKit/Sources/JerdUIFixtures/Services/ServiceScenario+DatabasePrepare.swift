import JerdDatabases
import JerdUI

extension ServiceScenario {
    /// Runs the steps of a database scenario after the launch. Returns false for the other scenarios.
    @MainActor
    func prepareDatabaseScenario(_ state: AppState) async -> Bool {
        let model = state.databases
        switch self {
        case .databaseEditor:
            model.beginAdd(.postgresql)
            await waitForPort(model)
        case .databaseEditorInvalid:
            model.beginAdd(.mysql)
            model.editor?.setName("Studio cache")
            model.editor?.setPort("6379")
        case .databaseStarting:
            model.start(SampleServices.reportingID)
        case .databaseCancelledSave:
            model.beginEdit(SampleServices.reportingID)
            model.saveEditor()
            model.closeEditor()
        case .databaseQuitting:
            _ = state.requestTermination { _ in }
        case .databaseRuntimeMissing:
            model.requestRemove(SampleServices.reportingID)
            await model.confirmRemove()?.value
        case .retainedDatabases:
            model.showRetained()
            await model.inspectRetained()?.value
        case .restoreDatabase:
            model.beginRestore(SampleServices.retained[0])
        default:
            return false
        }
        return true
    }
}
