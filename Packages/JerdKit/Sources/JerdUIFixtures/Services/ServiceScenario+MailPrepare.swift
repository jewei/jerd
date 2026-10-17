import JerdUI

extension ServiceScenario {
    /// Runs the steps of a mail scenario after the launch. Returns false for the other scenarios.
    @MainActor
    func prepareMailScenario(_ state: AppState) async -> Bool {
        let model = state.mail
        switch self {
        case .mail:
            await model.sendTestEmail()?.value
        case .mailPorts:
            await model.stop()?.value
            model.editPorts()
            model.portsDraft?.second = "1025"
        case .mailQuitting:
            _ = state.requestTermination { _ in }
        default:
            return false
        }
        return true
    }
}
