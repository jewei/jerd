import JerdDesign
import JerdServiceKit

extension MailModel: WorkspaceFeature, ShutdownParticipant {
    public var section: AppSection { .mail }
    public var shutdownPhase: ShutdownPhase { .mail }
    public var pollingPolicy: PollingPolicy { .services }
    public var shutdownParticipants: [any ShutdownParticipant] { [self] }
    public var bannerActivity: BannerActivity? { nil }

    /// The status of the page header, the card, and the menu.
    public var status: DisplayStatus {
        if loadState.failureMessage != nil { return DisplayStatus("Not loaded", tone: .failed) }
        if runtimeInstallation != nil { return DisplayStatus("Installing…", tone: .busy) }
        if loadState.isLoaded, !hasRuntime {
            return DisplayStatus(ServiceRuntimeCopy.notInstalledStatus, tone: .idle)
        }
        if cardNotice?.isPreparing == true { return ServiceCardNotice.preparingStatus }
        if operation.isWorking, !state.isBusy { return DisplayStatus(state.displayStatus.label, tone: .busy) }
        return state.displayStatus
    }

    public var summary: FeatureSummary {
        let text = cardNotice?.text ?? "SMTP port \(settings.smtpPort) · Web port \(settings.webPort)"
        return FeatureSummary(status: status, summary: text, actions: cardActions)
    }

    /// The card text while Mailpit cannot run yet: preparing, not loaded, installing, or not
    /// installed. With a pinned Mailpit, Start installs it first, so the card says so.
    var cardNotice: ServiceCardNotice? {
        if let runtimeInstallation, !hasRuntime {
            return ServiceCardNotice(
                text: runtimeInstallation.message, reason: "Jerd is installing Mailpit.", isPreparing: false)
        }
        let onDemand = runtimeOffer.map {
            ServiceCardNotice(
                text: ServiceRuntimeCopy.mail.cardNotice($0), reason: "Wait for the current mail work to end.",
                isPreparing: false)
        }
        return ServiceCardNotice.notice(
            load: loadState, hasRuntime: hasRuntime, runtime: "Mailpit", settings: "Mail", missingRuntime: onDemand)
    }

    /// Start, or Stop and Open Inbox while Mailpit runs (`CardActionRule`).
    private var cardActions: [FeatureAction] {
        guard state.offersStop else { return CardActionRule.actions(.start(lifecycleAction.titled("Start"))) }
        return CardActionRule.actions(.stop(lifecycleAction.titled("Stop")), open: inboxAction)
    }

    public var menuItems: [MenuBarItem] {
        [.submenu("Mail", id: "mail.menu", items: [.action(inboxAction), .action(lifecycleAction)])]
    }

    /// Start when stopped, Stop while a process is owned.
    var lifecycleAction: FeatureAction {
        if state.offersStop {
            return FeatureAction(id: "mail.stop", title: "Stop Mail", isEnabled: canStop) { [weak self] in
                self?.stop()
            }
        }
        return FeatureAction(
            id: "mail.start", title: "Start Mail", isEnabled: canStart, unavailableReason: startUnavailableReason
        ) {
            [weak self] in self?.start()
        }
    }

    /// Why Start is off: an installation on another page, then the card notice.
    var startUnavailableReason: String? {
        (startInstallsRuntime ? runtimeInstallElsewhere?() : nil) ?? cardNotice?.reason
    }

    var inboxAction: FeatureAction {
        FeatureAction(
            id: "mail.inbox", title: "Open Inbox", isEnabled: canOpenInbox, unavailableReason: inboxUnavailableReason
        ) {
            [weak self] in self?.openInbox()
        }
    }

    public func launch() async {
        await load()
    }

    /// Cancels a Mailpit installation before its final rename, waits for every running task, then
    /// stops Mailpit. False keeps Jerd open.
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
