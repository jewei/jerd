import JerdDesign
import SwiftUI

/// The ports sheet of mail and storage: two loopback ports, a free-port suggestion, the
/// two-port rule inline, and the save failure inline.
struct ServicePortsSheet: View {
    /// The words of one service's ports sheet.
    struct Copy {
        let title: String
        let message: String
        let firstLabel: String
        let secondLabel: String
        let footer: String
        /// The stable name of the sheet, for example `mail-ports`.
        let identifier: String
    }

    let copy: Copy
    @Binding var draft: PortsDraft
    let operation: OperationState
    let suggest: @MainActor () -> Void
    let save: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        SheetScaffold(
            copy.title, message: copy.message,
            confirmation: SheetConfirmation(
                "Save Ports", isEnabled: draft.ports != nil && !isQuitting, identifier: copy.identifier, perform: save),
            workingMessage: operation.workingMessage, cancel: cancel
        ) {
            Section {
                TextField(copy.firstLabel, text: $draft.first, prompt: Text(PortInput.prompt))
                    .accessibilityIdentifier("\(copy.identifier).first")
                TextField(copy.secondLabel, text: $draft.second, prompt: Text(PortInput.prompt))
                    .accessibilityIdentifier("\(copy.identifier).second")
                if let issue = draft.issue {
                    InlineMessage(issue, kind: .warning, identifier: "\(copy.identifier).issue")
                }
                ActionRow("Free ports", detail: "Finds the first two free ports from the defaults.") {
                    Button("Suggest Free Ports", action: suggest)
                        .disabled(isQuitting || operation.isWorking)
                        .accessibilityIdentifier("\(copy.identifier).suggest")
                }
            } footer: {
                FormFooter(copy.footer)
            }
            if let failure = operation.failureMessage {
                Section {
                    InlineMessage(failure, kind: .error, identifier: "\(copy.identifier).error")
                }
            }
        }
    }
}
