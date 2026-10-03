import SwiftUI
import JerdCore

struct TunnelDetailView: View {
    @Bindable var app: AppModel
    let tunnel: TunnelRegistration
    @State private var editing = false
    @State private var connecting = false
    @State private var removing = false
    @State private var showingLog = false

    private var model: TunnelModel { app.tunnels }
    private var state: TunnelState { model.state(tunnel) }
    private var site: Site? { app.configuration.sites.first { $0.id == tunnel.siteID } }

    var body: some View {
        GroupedPane(feedback: model.copiedMessage) {
            PaneHeader(tunnel.name, subtitle: "https://\(tunnel.hostname)", status: (state.title, state.tone)) {
                Button("Open website", systemImage: "safari") { model.open(tunnel) }
                if model.isActive(tunnel) {
                    Button("Stop", systemImage: "stop.fill") { model.stop(tunnel) }
                        .disabled(!model.canStop(tunnel) || state == .stopping)
                } else {
                    Button("Connect", systemImage: "play.fill") { connecting = true }
                        .primaryAction(model.canChange && model.configuration.runtime != nil)
                }
            }
        } content: {
            if let message = model.errorMessage {
                Section { InlineMessage(message) }
            }
            if case .failed(let message) = state {
                if message != model.errorMessage { Section { InlineMessage(message) } }
            }
            Section {
                ControlRow("Cloudflare connection", detail: "The connection from this Mac to Cloudflare.") {
                    StatusBadge(title: state.title, tone: state.tone)
                }
                ControlRow("Public address", detail: "https://\(tunnel.hostname)") {
                    Button("Copy URL", systemImage: "doc.on.doc") { model.copyURL(tunnel) }
                }
                ValueRow("Website health", "Not checked")
            } header: { Text("Connection") } footer: {
                Text("Connected means that Cloudflare accepts this connector. It does not confirm that your website responds. Other connectors can also serve this address.")
            }
            Section {
                if let site {
                    ControlRow("Jerd site", detail: site.displayName) {
                        Button("View site") {
                            app.selectedTunnelID = nil
                            app.selectedSiteID = site.id
                        }
                    }
                    ValueRow("Local address", "https://\(site.hostname)", monospaced: true)
                    ValueRow("Site environment", app.runningSiteIDs.contains(site.id) ? "Running" : "Not running")
                } else if tunnel.siteID != nil {
                    InlineMessage("The linked site was removed. Edit this registration to select a destination.")
                } else {
                    ValueRow("Local address", tunnel.originURL ?? "Not set", monospaced: true)
                }
                ControlRow("Cloudflare route", detail: "Check the published hostname and origin in Cloudflare.") {
                    Button("Open settings", systemImage: "arrow.up.right") { model.openCloudflare() }
                }
            } header: { Text("Destination reference") } footer: {
                Text("This destination is a reference for you. Jerd does not change DNS or tunnel routes. For local HTTPS, keep TLS verification on and configure the trusted CA and origin hostname in Cloudflare.")
            }
            Section("Startup") {
                ValueRow("Start when Jerd opens", tunnel.startOnLaunch ? "On" : "Off")
                ValueRow("Restart after an unexpected exit", tunnel.restartOnFailure ? "On" : "Off")
                Text("Closing the window keeps this connector running. Quit stops it. The Mac must remain awake and online to serve traffic.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ControlRow("cloudflared", detail: model.runtimeMessage) {
                    Button("Runtimes") { app.showDashboard(.runtimes) }
                    if model.configuration.runtime == nil {
                        Button("Choose executable…") { model.chooseRuntime() }.disabled(!model.canChange)
                    }
                }
                ControlRow("Connector log", detail: "View recent events from the connector owned by Jerd.") {
                    Button("View log") { showingLog = true }
                }
            } header: { Text("Runtime and diagnostics") }
            Section {
                ControlRow("Registration", detail: "Edit the token, destination reference, or startup settings.") {
                    Button("Edit…") { editing = true }.disabled(!model.canChange || model.isActive(tunnel))
                }
                ControlRow("Remove from Jerd", detail: "Keep the Cloudflare tunnel and DNS settings.") {
                    Button("Remove…", role: .destructive) { removing = true }.disabled(!model.canChange)
                }
            } footer: {
                if model.isActive(tunnel) { Text("Stop this connector before you edit its settings.") }
            }
        }
        .sheet(isPresented: $editing) { TunnelEditor(app: app, original: tunnel) }
        .sheet(isPresented: $showingLog) { TunnelLogView(model: model, tunnel: tunnel) }
        .confirmationDialog("Connect \(tunnel.name)?", isPresented: $connecting) {
            Button("Connect") { model.start(tunnel) }
        } message: {
            Text("Jerd will start another connector for this existing tunnel. Cloudflare can send traffic to it alongside any connector that is already running. Confirm that the existing routes point to services on this Mac.")
        }
        .confirmationDialog("Remove this tunnel from Jerd?", isPresented: $removing) {
            Button("Remove registration", role: .destructive) {
                model.remove(tunnel) {
                    if app.selectedTunnelID == tunnel.id { app.selectedTunnelID = nil }
                }
            }
        } message: {
            Text("Jerd will stop its connector and remove its saved token. The Cloudflare tunnel, DNS settings, and other connectors will remain.")
        }
    }
}

private struct TunnelLogView: View {
    let model: TunnelModel
    let tunnel: TunnelRegistration
    @Environment(\.dismiss) private var dismiss
    @State private var log = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(tunnel.name) log").font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }.disabled(loading)
            }
            if let error { InlineMessage(error) }
            ScrollView([.horizontal, .vertical]) {
                Text(log.isEmpty ? "No connector events yet." : log)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Recent events. Select Refresh to load new entries.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 720, height: 500)
        .task { await refresh() }
    }
    private func refresh() async {
        loading = true
        defer { loading = false }
        error = nil
        do { log = try await model.log(tunnel) }
        catch { self.error = error.localizedDescription }
    }
}
