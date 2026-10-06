import JerdDatabases
import JerdDesign
import JerdServiceKit
import SwiftUI

/// One database service: its status, connection values, Laravel settings, files, and its
/// registration. The header holds Start or Stop.
struct DatabaseDetailPage: View {
    let model: DatabasesModel
    let service: DatabaseService

    var body: some View {
        FormPage {
            PageHeader(
                service.name, subtitle: subtitle, status: NamedStatus("Database status", status),
                primaryAction: primaryAction, secondaryActions: secondaryActions
            ) {
                if model.busyServices.contains(service.id) {
                    BusyIndicator(state.offersStop ? "Stopping \(service.name)…" : "Starting \(service.name)…")
                }
            }
        } messages: {
            ServiceStateBanner(
                state: state, subject: service.name, stopTitle: "Stop Service", identifier: "database")
            if let message = model.operation.workingMessage {
                InlineMessage(message, kind: .info, style: .banner, identifier: "databases.working")
            }
            OperationFailureBanner(operation: model.operation, identifier: "databases.error") {
                model.dismissFailure()
            }
        } content: {
            if let runtime {
                DatabaseConnectionSection(model: model, service: service, engine: runtime.engine)
            }
            ServiceFilesSection(
                files: model.files[service.id],
                copy: .init(
                    logSubject: "\(service.name) log", missingData: "Start the service once to create its data folder.",
                    missingLog: "The service log is not available yet.",
                    footer: "Database files remain after Stop, Quit, or removal."),
                reveal: { model.revealData(service.id) }, openLog: { model.openLog(service.id) })
            DatabaseRegistrationSection(model: model, service: service)
        }
    }

    private var state: ServiceState { model.state(of: service.id) }
    private var runtime: DatabaseRuntime? { model.runtime(of: service) }

    private var status: DisplayStatus {
        model.displayStatus(of: service.id)
    }

    private var subtitle: String {
        guard let runtime else { return "Local database service" }
        return "\(runtime.engine.title) \(runtime.version) · Local database service"
    }

    /// Start when stopped; Stop only to retry a stop that did not finish. A running database
    /// has no single next step, so Stop is secondary then.
    private var primaryAction: PageAction? {
        if state.isRunning { return nil }
        if state.offersStop { return stopAction }
        return PageAction(
            "Start Service", systemImage: "play.fill", isEnabled: model.canStart(service.id),
            accessibilityLabel: "Start \(service.name)", identifier: "database.start"
        ) { model.start(service.id) }
    }

    private var secondaryActions: [PageAction] {
        state.isRunning ? [stopAction] : []
    }

    private var stopAction: PageAction {
        PageAction(
            "Stop Service", systemImage: "stop.fill", isEnabled: model.canStop(service.id),
            accessibilityLabel: "Stop \(service.name)", identifier: "database.stop"
        ) { model.stop(service.id) }
    }
}
