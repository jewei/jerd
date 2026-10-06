import JerdDesign
import SwiftUI

/// Installs `php`, `composer`, and `laravel` for zsh after a confirmation, and shows the report.
struct CommandLineToolsSection: View {
    @Bindable var model: CommandLineToolsModel

    var body: some View {
        Section {
            ActionRow("php, composer, and laravel", detail: model.stateDescription) {
                if model.operation.isWorking {
                    BusyIndicator(model.operation.workingMessage ?? "Installing…")
                }
                Button(model.actionTitle) { model.requestInstall() }
                    .disabled(!model.canInstall)
                    .accessibilityIdentifier("advanced.install-command-line-tools")
            }
            if let failure = model.operation.failureMessage {
                InlineMessage(failure, kind: .error, identifier: "advanced.command-line-tools.error")
            }
            if !model.report.isEmpty {
                InlineMessage(
                    model.report.joined(separator: "\n"), kind: .success,
                    identifier: "advanced.command-line-tools.report")
            }
        } header: {
            Text("Command-Line Tools")
        } footer: {
            FormFooter("Each command selects the PHP of the registered site that contains the working folder.")
        }
        .task { await model.load() }
        .confirmationDialog(
            "Install the command-line tools?", isPresented: $model.isConfirming, titleVisibility: .visible
        ) {
            Button("Install Tools") { model.install() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Jerd adds php, composer, and laravel to its own bin folder and adds one PATH block to your zsh startup files. It backs up each file before it changes it."
            )
        }
    }
}
