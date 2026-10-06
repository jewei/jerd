import JerdDesign
import SwiftUI

/// Dashboard › Advanced. Each section is its own view; every destructive step asks first.
struct AdvancedPage: View {
    @Bindable var model: AdvancedModel
    let commandLineTools: CommandLineToolsModel

    var body: some View {
        FormPage {
            PageHeader(
                "Advanced", subtitle: "Recover services, manage backups, and register local executables.",
                secondaryActions: [inspectAction])
        } messages: {
            if let message = model.operation.workingMessage {
                InlineMessage(message, kind: .info, style: .banner, identifier: "advanced.working")
            }
            OperationFailureBanner(operation: model.operation, identifier: "advanced.error") {
                model.dismissFailure()
            }
        } content: {
            if let status = model.httpsRecovery {
                HTTPSRecoverySection(model: model, status: status)
            }
            ProcessRecoverySection(model: model)
            RetainedBackupsSection(model: model)
            CommandLineToolsSection(model: commandLineTools)
            LocalExecutablesSection(model: model)
            PHPRegistrationsSection(model: model)
        }
        .confirmationDialog(
            model.confirmation?.title ?? "", isPresented: isConfirming, titleVisibility: .visible,
            presenting: model.confirmation
        ) { step in
            Button(step.confirmTitle, role: step.isDestructive ? .destructive : nil) {
                model.confirm()
            }
            .keyboardShortcut(step.isDestructive ? nil : .defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: { step in
            Text(step.message)
        }
    }

    private var inspectAction: PageAction {
        PageAction(
            "Inspect Recovery and Backups", systemImage: "magnifyingglass", isEnabled: model.isIdle,
            identifier: "advanced.inspect"
        ) {
            model.inspect()
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding {
            model.confirmation != nil
        } set: { isPresented in
            if !isPresented { model.confirmation = nil }
        }
    }
}
