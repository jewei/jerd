import JerdRuntimes
import JerdServiceKit
import JerdUI

/// The scenarios of an app that installs RustFS on demand.
extension ServiceScenario {
    /// True for the scenarios without RustFS that offer the pinned RustFS.
    var isStorageOnDemand: Bool {
        switch self {
        case .storageOnDemand, .storageOnDemandReuse, .storageInstalling, .storageInstallFailed,
            .dashboardStorageOnDemand:
            true
        default: false
        }
    }

    /// The storage of an on-demand scenario: no runtime and no buckets, as at first launch.
    func onDemandStorage() -> InMemoryStorage? {
        isStorageOnDemand ? InMemoryStorage() : nil
    }

    /// The offer and the install answer, before the launch reads them.
    func configureStorageOnDemand(_ storage: InMemoryStorage) async {
        guard isStorageOnDemand else { return }
        let base = SampleServices.storageOffer
        let offer =
            self == .storageOnDemandReuse
            ? StorageRuntimeOffer(
                versionLabel: base.versionLabel, downloadSize: base.downloadSize, source: base.source,
                installedSize: base.installedSize, reusesInstalledCopy: true)
            : base
        let behavior: InstallBehavior =
            switch self {
            case .storageInstalling:
                .suspend(
                    RuntimeInstallProgress(
                        RuntimePipeline.downloadMessage(base.title, fraction: 0.42, size: .exact(base.downloadSize)),
                        0.42))
            case .storageInstallFailed: .fail(Self.offlineMessage)
            default: .succeed
            }
        await storage.configure {
            $0.offer = offer
            $0.installBehavior = behavior
        }
    }

    /// Runs the steps of an on-demand storage scenario. Returns false for the other scenarios.
    @MainActor
    func prepareStorageOnDemand(_ state: AppState) async -> Bool {
        let model = state.storage
        switch self {
        case .storageInstalling:
            model.requestRuntimeInstall(startsStorage: true)
            model.confirmRuntimeInstall()
        case .storageInstallFailed:
            model.requestRuntimeInstall()
            await model.confirmRuntimeInstall()?.value
        default:
            return isStorageOnDemand
        }
        return true
    }

    /// True when an on-demand storage scenario shows its state; nil for the other scenarios.
    @MainActor
    func isStorageOnDemandReady(_ state: AppState) -> Bool? {
        guard isStorageOnDemand else { return nil }
        let model = state.storage
        switch self {
        case .storageInstalling: return model.runtimeInstallation?.progress != nil
        case .storageInstallFailed: return model.runtimeNotice != nil
        default: return model.runtimeOffer != nil
        }
    }
}
