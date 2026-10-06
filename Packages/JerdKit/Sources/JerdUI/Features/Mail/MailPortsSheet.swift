import JerdDesign
import SwiftUI

/// The mail ports sheet. Package access lets the snapshot catalog render it alone.
package struct MailPortsSheet: View {
    @Bindable var model: MailModel

    package init(model: MailModel) {
        self.model = model
    }

    package var body: some View {
        ServicePortsSheet(
            copy: .init(
                title: "Mail Ports",
                message: "Changing ports keeps the inbox. Update your application's mail settings after a change.",
                firstLabel: "SMTP port", secondLabel: "Web port",
                footer: "Both ports listen only on 127.0.0.1. The defaults are SMTP 1025 and web 8025.",
                identifier: "mail-ports"),
            draft: draft, operation: model.portsOperation, suggest: { model.suggestPorts() },
            save: { model.savePorts() }, cancel: model.cancelPorts)
    }

    private var draft: Binding<PortsDraft> {
        Binding {
            model.portsDraft ?? PortsDraft(first: "", second: "")
        } set: { draft in
            model.portsDraft = draft
        }
    }
}
