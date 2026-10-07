import JerdRuntimes
import JerdServiceKit
import JerdUI

/// The scenarios of an app that installs Mailpit on demand.
extension ServiceScenario {
    /// True for the scenarios without Mailpit that offer the pinned Mailpit.
    var isMailOnDemand: Bool {
        switch self {
        case .mailOnDemand, .mailOnDemandReuse, .mailInstalling, .mailInstallFailed, .dashboardMailOnDemand: true
        default: false
        }
    }

    /// The mail of an on-demand scenario: no runtime and no inbox, as at first launch.
    func onDemandMail() -> InMemoryMail? {
        isMailOnDemand ? InMemoryMail() : nil
    }

    /// The offer and the install answer, before the launch reads them.
    func configureMailOnDemand(_ mail: InMemoryMail) async {
        guard isMailOnDemand else { return }
        let base = SampleServices.mailOffer
        let offer = self == .mailOnDemandReuse ? base.reusing() : base
        let behavior: InstallBehavior =
            switch self {
            case .mailInstalling:
                .suspend(
                    RuntimeInstallProgress(
                        RuntimePipeline.downloadMessage(base.title, fraction: 0.42, size: .exact(base.downloadSize)),
                        0.42))
            case .mailInstallFailed: .fail(Self.offlineMessage)
            default: .succeed
            }
        await mail.configure {
            $0.offer = offer
            $0.installBehavior = behavior
        }
    }

    /// Runs the steps of an on-demand mail scenario. Returns false for the other scenarios.
    @MainActor
    func prepareMailOnDemand(_ state: AppState) async -> Bool {
        let model = state.mail
        switch self {
        case .mailInstalling:
            model.requestRuntimeInstall(startsService: true)
            model.confirmRuntimeInstall()
        case .mailInstallFailed:
            model.requestRuntimeInstall()
            await model.confirmRuntimeInstall()?.value
        default:
            return isMailOnDemand
        }
        return true
    }

    /// True when an on-demand mail scenario shows its state; nil for the other scenarios. The
    /// first-launch dashboard also waits for the storage and database offers.
    @MainActor
    func isMailOnDemandReady(_ state: AppState) -> Bool? {
        guard isMailOnDemand else { return nil }
        let model = state.mail
        switch self {
        case .mailInstalling: return model.runtimeInstallation?.progress != nil
        case .mailInstallFailed: return model.runtimeNotice != nil
        case .dashboardMailOnDemand:
            return model.runtimeOffer != nil && state.storage.runtimeOffer != nil
                && !state.databases.runtimeOffers.isEmpty
        default: return model.runtimeOffer != nil
        }
    }
}
