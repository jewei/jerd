import JerdDesign
import JerdServiceKit

extension StorageModel: WorkspaceFeature, ShutdownParticipant {
    public var section: AppSection { .storage }
    public var shutdownPhase: ShutdownPhase { .storage }
    public var pollingPolicy: PollingPolicy { .services }
    public var shutdownParticipants: [any ShutdownParticipant] { [self] }
    public var bannerActivity: BannerActivity? { nil }

    public var status: DisplayStatus {
        if loadState.failureMessage != nil { return DisplayStatus("Not loaded", tone: .failed) }
        let working = operation.isWorking || bucketOperation.isWorking
        if working, !state.isBusy { return DisplayStatus(state.displayStatus.label, tone: .busy) }
        return state.displayStatus
    }

    public var summary: FeatureSummary {
        let count = buckets.count == 1 ? "1 bucket" : "\(buckets.count) buckets"
        let text =
            hasRuntime ? "\(count) · S3 port \(settings.apiPort)" : "RustFS is not installed. Install it in Runtimes."
        return FeatureSummary(status: status, summary: text, actions: [lifecycleAction, consoleAction])
    }

    public var menuItems: [MenuBarItem] {
        [.submenu("Storage", id: "storage.menu", items: [.action(consoleAction), .action(lifecycleAction)])]
    }

    var lifecycleAction: FeatureAction {
        if state.offersStop {
            return FeatureAction(id: "storage.stop", title: "Stop Storage", isEnabled: canStop) { [weak self] in
                self?.stop()
            }
        }
        return FeatureAction(id: "storage.start", title: "Start Storage", isEnabled: canStart, isPrimary: canStart) {
            [weak self] in self?.start()
        }
    }

    var consoleAction: FeatureAction {
        FeatureAction(
            id: "storage.console", title: "Open Console", isEnabled: canOpenConsole, isPrimary: canOpenConsole
        ) { [weak self] in self?.openConsole() }
    }

    public func launch() async {
        await load()
    }

    /// Waits for every running task, then stops RustFS. False keeps Jerd open.
    public func shutdown() async -> Bool {
        isShuttingDown = true
        await running.waitForAll()
        guard loadState.isLoaded, state != .stopped else { return true }
        do {
            try await port.stop()
            await refresh()
            return true
        } catch {
            await refresh()
            operation = state.needsAttention ? .idle : .failed(message: ErrorText.message(for: error))
            return false
        }
    }

    public func resumeAfterCancelledQuit() {
        isShuttingDown = false
    }
}
