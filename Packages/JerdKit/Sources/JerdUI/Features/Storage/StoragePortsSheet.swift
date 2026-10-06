import SwiftUI

/// The storage ports sheet. Package access lets the snapshot catalog render it alone.
package struct StoragePortsSheet: View {
    @Bindable var model: StorageModel

    package init(model: StorageModel) {
        self.model = model
    }

    package var body: some View {
        ServicePortsSheet(
            copy: .init(
                title: "Storage Ports",
                message:
                    "Changing ports keeps all buckets and objects. Update your application's endpoint after a change.",
                firstLabel: "S3 port", secondLabel: "Console port",
                footer: "Both ports listen only on 127.0.0.1. The defaults are S3 9000 and console 9001.",
                identifier: "storage-ports"),
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
