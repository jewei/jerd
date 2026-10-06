import JerdDatabases
import JerdDesign
import JerdServiceKit

/// The controls of a database page header: Start when stopped; Stop only to retry a stop that
/// did not finish. A running database has no single next step, so Stop is secondary then.
/// During a quit, Start and Stop are off.
@MainActor
struct DatabaseHeaderActions {
    let model: DatabasesModel
    let service: DatabaseService
    let isQuitting: Bool

    var primary: PageAction? {
        if state.isRunning { return nil }
        if state.offersStop { return stop }
        return PageAction(
            "Start Service", systemImage: "play.fill", isEnabled: model.canStart(service.id) && !isQuitting,
            accessibilityLabel: "Start \(service.name)", identifier: "database.start"
        ) { model.start(service.id) }
    }

    var secondary: [PageAction] {
        state.isRunning ? [stop] : []
    }

    private var state: ServiceState { model.state(of: service.id) }

    private var stop: PageAction {
        PageAction(
            "Stop Service", systemImage: "stop.fill", isEnabled: model.canStop(service.id) && !isQuitting,
            accessibilityLabel: "Stop \(service.name)", identifier: "database.stop"
        ) { model.stop(service.id) }
    }
}
