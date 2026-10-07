import JerdDesign
import SwiftUI

/// Registers trusted local PHP and Caddy executables. The bundled runtimes need none of this.
struct LocalExecutablesSection: View {
    let model: AdvancedModel

    var body: some View {
        Section {
            if let message = model.registrations.setupMessage {
                InlineMessage(message, kind: .info)
            }
            ActionRow("PHP CLI and FPM", detail: "Select a PHP CLI and its matching PHP-FPM.") {
                Button("Select PHP CLI and FPM…") { model.choosePHP() }
                    .disabled(!model.isIdle)
                    .accessibilityIdentifier("advanced.select-php")
            }
            ActionRow("Caddy", detail: model.registrations.caddyVersion.map { "Caddy \($0) is registered." }) {
                Button("Select Caddy…") { model.chooseCaddy() }
                    .disabled(!model.isIdle)
                    .accessibilityIdentifier("advanced.select-caddy")
            }
        } header: {
            Text("Local Executables")
        } footer: {
            FormFooter("Select trusted executables for development. Jerd runs them only to check their versions.")
        }
    }
}
