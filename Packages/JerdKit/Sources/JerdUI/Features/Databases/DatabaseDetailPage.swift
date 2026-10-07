import JerdDatabases
import JerdDesign
import JerdServiceKit
import SwiftUI

/// One database service: its status, connection values, Laravel settings, files, and its
/// registration. The header holds Start or Stop (`DatabaseHeaderActions`).
struct DatabaseDetailPage: View {
    let model: DatabasesModel
    let service: DatabaseService
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        let actions = DatabaseHeaderActions(model: model, service: service, isQuitting: isQuitting)
        FormPage {
            PageHeader(
                service.name, subtitle: subtitle, status: NamedStatus("Database status", status),
                primaryAction: actions.primary, secondaryActions: actions.secondary
            ) {
                if model.busyServices.contains(service.id) {
                    BusyIndicator(state.offersStop ? "Stopping \(service.name)…" : "Starting \(service.name)…")
                }
            }
        } messages: {
            DatabasesPageMessages(model: model, service: service)
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
}
