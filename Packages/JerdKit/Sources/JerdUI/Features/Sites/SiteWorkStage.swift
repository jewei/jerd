/// The first stage of the staged quit: it ends the current site operation. A change that
/// can stop ends at its next step; an HTTPS approval waits for the macOS prompt.
@MainActor
final class SiteWorkStage: ShutdownParticipant {
    private weak var model: SitesModel?

    init(model: SitesModel) {
        self.model = model
    }

    var shutdownPhase: ShutdownPhase { .siteWork }

    var shutdownMessage: String {
        guard let operation = model?.operation, operation.isWorking else { return ShutdownPhase.siteWork.message }
        if case .working(_, true) = operation { return ShutdownPhase.siteWork.message }
        return "Waiting for system setup. Complete or cancel the macOS approval prompt…"
    }

    func shutdown() async -> Bool {
        guard let model else { return true }
        model.isShuttingDown = true
        if case .working(_, true) = model.operation {
            await model.port.requestStop()
        }
        await model.currentWork?.value
        return true
    }

    func resumeAfterCancelledQuit() {
        model?.isShuttingDown = false
    }
}
