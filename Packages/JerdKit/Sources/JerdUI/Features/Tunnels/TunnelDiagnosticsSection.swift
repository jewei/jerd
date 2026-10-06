import JerdDesign
import JerdTunnels
import SwiftUI

/// The cloudflared runtime and the connector log.
struct TunnelDiagnosticsSection: View {
    let state: AppState
    let model: TunnelsModel
    let tunnel: TunnelRegistration

    var body: some View {
        Section("Runtime and Diagnostics") {
            ActionRow("cloudflared", detail: model.runtimeMessage) {
                Button("Runtimes") { state.navigation.show(.dashboard(.runtimes)) }
                    .accessibilityLabel("Manage runtimes")
                if model.configuration.runtime == nil {
                    Button("Choose Executable…") { model.chooseRuntime() }
                        .disabled(!model.canChange)
                        .accessibilityIdentifier("tunnel.choose-runtime")
                }
            }
            ActionRow("Connector log", detail: "Recent events from the connector that Jerd owns.") {
                Button("View Log", systemImage: "doc.text") { model.showLog(tunnel) }
                    .accessibilityIdentifier("tunnel.view-log")
            }
        }
    }
}
