import SwiftUI
import JerdCore

struct TunnelEditor: View {
    let app: AppModel
    let original: TunnelRegistration?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var hostname: String
    @State private var token = ""
    @State private var siteID: UUID?
    @State private var originURL: String
    @State private var startOnLaunch: Bool
    @State private var restartOnFailure: Bool
    @State private var metricsPort: UInt16?
    @State private var portError: String?
    @State private var confirmed = false

    init(app: AppModel, original: TunnelRegistration? = nil) {
        self.app = app
        self.original = original
        _name = State(initialValue: original?.name ?? "")
        _hostname = State(initialValue: original?.hostname ?? "")
        _siteID = State(initialValue: original?.siteID)
        _originURL = State(initialValue: original?.originURL ?? "http://127.0.0.1:8000")
        _startOnLaunch = State(initialValue: original?.startOnLaunch ?? false)
        _restartOnFailure = State(initialValue: original?.restartOnFailure ?? true)
        _metricsPort = State(initialValue: original?.metricsPort)
    }
    private var model: TunnelModel { app.tunnels }
    private var canSave: Bool {
        model.canChange && metricsPort != nil && confirmed && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (original != nil || !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (siteID == nil || app.configuration.sites.contains(where: { $0.id == siteID }))
    }

    var body: some View {
        SheetScaffold(title: original == nil ? "Add Cloudflare tunnel" : "Edit Cloudflare tunnel",
                      message: "Connect an existing tunnel to this Mac.", width: 620) {
            Section {
                TextField("Name", text: $name, prompt: Text("Remakan preview"))
                TextField("Public hostname", text: $hostname, prompt: Text("remakan.dev"))
                SecureField(original == nil ? "Tunnel token" : "Replace token", text: $token,
                            prompt: Text(original == nil ? "Paste the token from Cloudflare" : "Leave empty to keep the saved token"))
            } header: { Text("Existing tunnel") } footer: {
                Text("The hostname and route must already exist in Cloudflare. Tokens are stored in your macOS Keychain.")
            }
            Section {
                Picker("Local destination", selection: $siteID) {
                    Text("Local HTTP or HTTPS address").tag(nil as UUID?)
                    ForEach(app.configuration.sites) { site in
                        Text(site.displayName).tag(Optional(site.id))
                    }
                    if let siteID, !app.configuration.sites.contains(where: { $0.id == siteID }) {
                        Text("Removed site — choose a destination").tag(Optional(siteID))
                    }
                }
                if siteID == nil {
                    TextField("Local address", text: $originURL, prompt: Text("http://127.0.0.1:8000"))
                } else if let site = app.configuration.sites.first(where: { $0.id == siteID }) {
                    ValueRow("Local address", "https://\(site.hostname)", monospaced: true)
                }
            } header: { Text("Destination reference") } footer: {
                Text("Match this reference to the route in Cloudflare. Saving here does not change DNS, routing, or TLS settings.")
            }
            Section("Startup") {
                Toggle("Start when Jerd opens", isOn: $startOnLaunch)
                Toggle("Restart after an unexpected exit", isOn: $restartOnFailure)
            }
            Section {
                Toggle("I checked the existing route for this Mac.", isOn: $confirmed)
                Text("Starting another connector can share traffic with a connector that is already running. Save adds the registration. Select Connect when you are ready.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Cloudflare settings", systemImage: "arrow.up.right") { model.openCloudflare() }
            }
            if let error = model.errorMessage { InlineMessage(error) }
            if let portError { InlineMessage(portError) }
        } footer: {
            Button("Cancel") { token = ""; dismiss() }.keyboardShortcut(.cancelAction).disabled(model.isBusy)
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button("Save registration") { save() }.keyboardShortcut(.defaultAction).primaryAction(canSave)
        }
        .frame(height: 650)
        .interactiveDismissDisabled(model.isBusy)
        .task {
            model.errorMessage = nil
            guard metricsPort == nil else { return }
            do { metricsPort = try await model.suggestedPort() }
            catch { portError = error.localizedDescription }
        }
    }
    private func save() {
        guard let metricsPort, canSave else { return }
        let registration = TunnelRegistration(
            id: original?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            hostname: hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), siteID: siteID,
            originURL: siteID == nil ? originURL.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            startOnLaunch: startOnLaunch, restartOnFailure: restartOnFailure, metricsPort: metricsPort)
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        model.save(registration, token: secret.isEmpty ? nil : secret) {
            token = ""
            app.showTunnel(registration.id)
            dismiss()
        }
    }
}
