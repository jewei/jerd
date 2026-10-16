import JerdDesign
import JerdTunnels
import SwiftUI

/// Where a new tunnel comes from. "Create in Cloudflare" connects the account once with an API
/// token, then asks only for a domain and a subdomain.
struct TunnelEditorSourceSection: View {
    let model: TunnelsModel
    @Bindable var editor: TunnelEditorModel

    var body: some View {
        Section {
            Picker("Source", selection: $editor.source) {
                ForEach(TunnelSource.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("tunnel-editor.source")
            if editor.source == .create {
                switch editor.isCloudflareConnected {
                case .some(true): account
                case .some(false): connect
                case .none: ProgressView().controlSize(.small)
                }
            }
        } header: {
            Text("Cloudflare")
        } footer: {
            FormFooter(footer)
        }
    }

    private var connect: some View {
        Group {
            SecureField("API token", text: $editor.apiToken, prompt: Text("Paste a Cloudflare API token"))
                .accessibilityIdentifier("tunnel-editor.api-token")
            ActionRow("Connect Cloudflare", detail: Self.permissions) {
                Button("Create Token", systemImage: "arrow.up.right") { model.openCloudflareTokenPage() }
                Button("Connect") { model.connectCloudflare(editor) }
                    .disabled(editor.apiTokenToConnect == nil || !model.canChange)
                    .accessibilityIdentifier("tunnel-editor.connect-cloudflare")
            }
        }
    }

    private var account: some View {
        Group {
            Picker("Domain", selection: $editor.zoneID) {
                ForEach(editor.zones) { Text($0.name).tag(String?.some($0.id)) }
            }
            TextField("Subdomain", text: $editor.subdomain, prompt: Text("dev"))
                .accessibilityIdentifier("tunnel-editor.subdomain")
            ValueRow("Public address", value: "https://\(editor.publicHostname)", isCode: true)
            ActionRow("Cloudflare account", detail: "Jerd keeps the API token in your macOS Keychain.") {
                Button("Disconnect") { model.disconnectCloudflare(editor) }.disabled(!model.canChange)
            }
        }
    }

    /// The permissions of the API token, in the words of the Cloudflare token page.
    static let permissions =
        "Create a token with Account › Cloudflare Tunnel › Edit, Zone › DNS › Edit, and Zone › Zone › Read."

    private var footer: String {
        switch editor.source {
        case .create:
            "Jerd creates a tunnel and a DNS record for this address, and never replaces an existing record. Then it connects the tunnel."
        case .existing:
            "Paste the token of a tunnel that you made in Cloudflare. Its public hostname must already point to it."
        }
    }
}
