import JerdDesign

/// The controls of the Mail page header. The next step is primary: Start when stopped, Open
/// Inbox when running, Stop to retry a stop that did not finish. During a quit, Start and Stop
/// are off; Open Inbox starts no work.
@MainActor
struct MailHeaderActions {
    let model: MailModel
    let isQuitting: Bool

    var primary: PageAction? {
        if model.state.isRunning { return inbox }
        if model.state.offersStop { return stop }
        return PageAction(
            "Start Mail", systemImage: "play.fill", isEnabled: model.canStart && !isQuitting, identifier: "mail.start"
        ) { model.start() }
    }

    var secondary: [PageAction] {
        model.state.isRunning ? [stop] : []
    }

    private var stop: PageAction {
        PageAction(
            "Stop Mail", systemImage: "stop.fill", isEnabled: model.canStop && !isQuitting, identifier: "mail.stop"
        ) { model.stop() }
    }

    private var inbox: PageAction {
        PageAction(
            "Open Inbox", systemImage: "tray", isEnabled: model.canOpenInbox, identifier: "mail.open-inbox"
        ) { model.openInbox() }
    }
}
