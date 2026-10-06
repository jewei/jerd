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
        if operation.isWorking, !state.isBusy { return DisplayStatus(state.displayStatus.label, tone: .busy) }
        return state.displayStatus
    }

    public var summary: FeatureSummary {
        let text =
            hasRuntime
            ? "SMTP port \(settings.smtpPort) · Web port \(settings.webPort)"
            : "Mailpit is not installed. Install it in Runtimes."
        return FeatureSummary(status: status, summary: text, actions: [lifecycleAction, inboxAction])
    }

    public var menuItems: [MenuBarItem] {
        [.submenu("Mail", id: "mail.menu", items: [.action(inboxAction), .action(lifecycleAction)])]
    }

    /// Start when stopped, Stop while a process is owned. Start is the next step when stopped.
    var lifecycleAction: FeatureAction {
        if state.offersStop {
            return FeatureAction(id: "mail.stop", title: "Stop Mail", isEnabled: canStop) { [weak self] in
                self?.stop()
            }
        }
        return FeatureAction(id: "mail.start", title: "Start Mail", isEnabled: canStart, isPrimary: canStart) {
            [weak self] in self?.start()
        }
    }

    var inboxAction: FeatureAction {
        FeatureAction(id: "mail.inbox", title: "Open Inbox", isEnabled: canOpenInbox, isPrimary: canOpenInbox) {
            [weak self] in self?.openInbox()
        }
    }

    public func launch() async {
        await load()
    }

    /// Waits for every running task, then stops Mailpit. False keeps Jerd open.
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
