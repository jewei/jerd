import JerdDatabases
import JerdDesign
import SwiftUI

/// The Databases page without a selected service: loading, no services, or a prompt to select.
struct DatabasesEmptyPage: View {
    let model: DatabasesModel

    var body: some View {
        VStack(spacing: 0) {
            if let message = model.loadState.failureMessage {
                InlineMessage(message, kind: .error, style: .banner, identifier: "databases.load-error")
                    .padding(Spacing.large)
            }
            OperationFailureBanner(operation: model.operation, identifier: "databases.error") {
                model.dismissFailure()
            }
            .padding(.horizontal, Spacing.large)
            EmptyState(title, systemImage: "cylinder.split.1x2", message: message) {
                if model.loadState.isLoaded, model.services.isEmpty {
                    actions
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var actions: some View {
        if model.availableEngines.isEmpty {
            Button("View Runtimes", systemImage: "shippingbox") { model.showRuntimes() }
                .primaryActionStyle(isEnabled: true)
        } else {
            // One column of equal widths: the widest title sets the width of every button.
            VStack(spacing: Spacing.small) {
                ForEach(Array(model.availableEngines.enumerated()), id: \.element) { index, engine in
                    Button {
                        model.beginAdd(engine)
                    } label: {
                        Text("Add \(engine.title)…")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryActionStyle(isPrimary: index == 0, isEnabled: model.canAdd)
                    .accessibilityIdentifier(AccessibilityIdentifier.make("databases", "add", engine.title))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var title: String {
        switch model.loadState {
        case .loading: "Preparing Databases"
        case .failed: "Databases Not Loaded"
        case .loaded: model.services.isEmpty ? "Your Local Databases" : "Select a Database"
        }
    }

    private var message: String {
        switch model.loadState {
        case .loading: "Checking MySQL, PostgreSQL, and Redis runtimes…"
        case .failed: "Jerd keeps the settings file as it is. Check the message above."
        case .loaded:
            if !model.services.isEmpty {
                "Select a database service in the sidebar."
            } else if model.availableEngines.isEmpty {
                "Install a MySQL, PostgreSQL, or Redis runtime in Runtimes first."
            } else {
                "Run MySQL, PostgreSQL, and Redis with a separate data folder, port, and password for each service."
            }
        }
    }
}
