import JerdDesign
import SwiftUI

/// The name, hostname, token, and metrics port of a tunnel. The token is never shown again. A
/// tunnel that Jerd creates gets its hostname from the Cloudflare section and needs no token.
struct TunnelEditorTunnelSection: View {
    @Bindable var editor: TunnelEditorModel

    var body: some View {
        Section {
            TextField(
                "Name", text: $editor.name,
                prompt: Text(editor.isCreating ? editor.publicHostname : "Studio preview"))
            if !editor.isCreating {
                TextField("Public hostname", text: $editor.hostname, prompt: Text("preview.example.com"))
                    .disabled(editor.original?.cloudflare != nil)
                SecureField(
                    editor.isNew ? "Tunnel token" : "Replace token", text: $editor.token,
                    prompt: Text(
                        editor.isNew ? "Paste the token from Cloudflare" : "Leave empty to keep the saved token"))
            }
            TextField("Metrics port", text: $editor.metricsPort, prompt: Text("20241"))
        } header: {
            Text(editor.isCreating ? "Tunnel" : "Existing Tunnel")
        } footer: {
            FormFooter(
                editor.isCreating
                    ? "Jerd keeps the tunnel token in your macOS Keychain."
                    : "The public hostname must already point to this tunnel in Cloudflare. Jerd keeps the token in your macOS Keychain."
            )
        }
    }
}
