import JerdDesign
import JerdServiceKit

extension StorageModel: WorkspaceFeature, ShutdownParticipant {
    public var section: AppSection { .storage }
    public var shutdownPhase: ShutdownPhase { .storage }
    public var pollingPolicy: PollingPolicy { .services }
    public var shutdownParticipants: [any ShutdownParticipant] { [self] }
    public var bannerActivity: BannerActivity? { nil }

    /// File › New Bucket… (⌘N): the Add Bucket sheet. It is off while a sheet shows, so it
    /// never replaces a draft.
    public var newItemAction: FeatureAction? {
        FeatureAction(id: "storage.new", title: "New Bucket…", isEnabled: canAddBucket && !isShowingSheet) {
            [weak self] in
            self?.beginAddBucket()
        }
    }

    public var status: DisplayStatus {
        if loadState.failureMessage != nil { return DisplayStatus("Not loaded", tone: .failed) }
        if runtimeInstallation != nil { return DisplayStatus("Installing…", tone: .busy) }
        if cardNotice?.isPreparing == true { return ServiceCardNotice.preparingStatus }
        let working = operation.isWorking || bucketOperation.isWorking
        if working, !state.isBusy { return DisplayStatus(state.displayStatus.label, tone: .busy) }
        return state.displayStatus
    }

    public var summary: FeatureSummary {
        let count = buckets.count == 1 ? "1 bucket" : "\(buckets.count) buckets"
        let text = cardNotice?.text ?? "\(count) · S3 port \(settings.apiPort)"
        return FeatureSummary(status: status, summary: text, actions: cardActions)
    }

    /// The card text while RustFS cannot run yet: preparing, not loaded, installing, or not
    /// installed. With a pinned RustFS, Start installs it first, so the card says so.
    var cardNotice: ServiceCardNotice? {
        if let runtimeInstallation, !hasRuntime {
            return ServiceCardNotice(
                text: runtimeInstallation.message, reason: "Jerd is installing RustFS.", isPreparing: false)
        }
        let onDemand = runtimeOffer.map {
            ServiceCardNotice(
                text: StorageRuntimeCopy.cardNotice($0), reason: "Wait for the current storage work to end.",
                isPreparing: false)
        }
        return ServiceCardNotice.notice(
            load: loadState, hasRuntime: hasRuntime, runtime: "RustFS", settings: "Storage", missingRuntime: onDemand)
    }

    /// Start, or Stop and Open Console while RustFS runs (`CardActionRule`).
    private var cardActions: [FeatureAction] {
        guard state.offersStop else { return CardActionRule.actions(.start(lifecycleAction.titled("Start"))) }
        return CardActionRule.actions(.stop(lifecycleAction.titled("Stop")), open: consoleAction)
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
        return FeatureAction(
            id: "storage.start", title: "Start Storage", isEnabled: canStart, unavailableReason: startUnavailableReason
        ) {
            [weak self] in self?.start()
        }
    }

    /// Why Start is off: an installation on another page, then the card notice.
    var startUnavailableReason: String? {
        (startInstallsRuntime ? runtimeInstallElsewhere?() : nil) ?? cardNotice?.reason
    }

    var consoleAction: FeatureAction {
        FeatureAction(id: "storage.console", title: "Open Console", isEnabled: canOpenConsole) { [weak self] in
            self?.openConsole()
        }
    }

    public func launch() async {
        await load()
    }

    /// Cancels a RustFS installation before its final rename, waits for every running task, then
    /// stops RustFS. False keeps Jerd open.
    public func shutdown() async -> Bool {
        isShuttingDown = true
        pendingRuntimeInstall = nil
        cancelRuntimeInstall()
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
