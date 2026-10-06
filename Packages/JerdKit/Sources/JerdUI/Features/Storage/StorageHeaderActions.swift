import JerdDesign

/// The storage controls of both Storage pages. The next step is primary: Start when stopped,
/// Open Console when running, Stop to retry a stop that did not finish.
@MainActor
struct StorageHeaderActions {
    let model: StorageModel

    var primary: PageAction? {
        if model.state.isRunning { return console }
        if model.state.offersStop { return stop }
        return PageAction(
            "Start Storage", systemImage: "play.fill", isEnabled: model.canStart, identifier: "storage.start"
        ) { model.start() }
    }

    var secondary: [PageAction] {
        model.state.isRunning ? [stop] : []
    }

    private var stop: PageAction {
        PageAction("Stop Storage", systemImage: "stop.fill", isEnabled: model.canStop, identifier: "storage.stop") {
            model.stop()
        }
    }

    private var console: PageAction {
        PageAction(
            "Open Console", systemImage: "arrow.up.right.square", isEnabled: model.canOpenConsole,
            identifier: "storage.open-console"
        ) { model.openConsole() }
    }
}
