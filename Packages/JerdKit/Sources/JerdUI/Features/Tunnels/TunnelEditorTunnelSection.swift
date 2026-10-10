import JerdDesign
import SwiftUI

/// The name, hostname, token, and metrics port of a tunnel. The token is never shown again.
struct TunnelEditorTunnelSection: View {
    @Bindable var editor: TunnelEditorModel

    var body: some View {
        Section {
            TextField("Name", text: $editor.name, prompt: Text("Studio preview"))
            TextField("Public hostname", text: $editor.hostname, prompt: Text("preview.example.com"))
            SecureField(
                editor.isNew ? "Tunnel token" : "Replace token", text: $editor.token,
                prompt: Text(editor.isNew ? "Paste the token from Cloudflare" : "Leave empty to keep the saved token"))
            TextField("Metrics port", text: $editor.metricsPort, prompt: Text("20241"))
        } header: {
            Text("Existing Tunnel")
        } footer: {
            FormFooter(
                "The public hostname must already point to this tunnel in Cloudflare. Jerd keeps the token in your macOS Keychain."
            )
        }
    }
}
