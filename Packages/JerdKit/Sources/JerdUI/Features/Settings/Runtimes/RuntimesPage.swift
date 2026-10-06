import JerdDesign
import JerdManifest
import SwiftUI

/// Dashboard › Runtimes: one section per runtime kind, in catalog order.
struct RuntimesPage: View {
    let model: RuntimesModel

    var body: some View {
        FormPage {
            PageHeader(
                "Runtimes", subtitle: "Manage the tools that power your local environment.",
                secondaryActions: [checkAction]
            ) {
                if model.isChecking {
                    BusyIndicator("Checking for runtime updates")
                }
            }
        } messages: {
            if let installation = model.installation {
                InlineMessage(
                    "Installing \(installation.kind.title). Other runtime changes wait until it finishes.", kind: .info,
                    style: .banner, identifier: "runtimes.installing")
            }
            OperationFailureBanner(operation: model.operation, identifier: "runtimes.error") {
                model.dismissFailure()
            }
        } content: {
            ForEach(RuntimeKind.allCases) { kind in
                RuntimeSection(model: model, kind: kind)
            }
        }
        // Advanced and the services can change what is installed, so read it each time.
        .task { await model.load() }
    }

    private var checkAction: PageAction {
        PageAction(
            "Check for Updates", systemImage: "arrow.clockwise", isEnabled: model.canCheck,
            accessibilityLabel: "Check for runtime updates", identifier: "runtimes.check"
        ) {
            model.check()
        }
    }
}
