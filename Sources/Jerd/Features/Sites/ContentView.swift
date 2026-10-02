import SwiftUI
import AppKit
import JerdCore
import ServiceManagement

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var editingSite: Site?
    @State private var removingSite: Site?
    @State private var removingSetup = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedSiteID) {
                ForEach(model.configuration.sites) { site in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(site.displayName).font(.headline)
                        Text(site.hostname).foregroundStyle(.secondary)
                        if !site.isEnabled { Text("Disabled").font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 5)
                    .tag(site.id)
                }
            }
            .navigationTitle("Sites")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        editingSite = Site(displayName: "", projectPath: "", documentRoot: "", hostname: "")
                    } label: { Label("Add site", systemImage: "plus") }
                    .disabled(!model.isLoaded || model.isBusy)
                    Spacer()
                }.padding()
            }
        } detail: {
            if let site = model.selectedSite {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(site.displayName).font(.largeTitle.bold())
                                Text("https://\(site.hostname)").font(.title3).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(site.isEnabled ? "Enabled" : "Disabled").font(.callout)
                        }
                        setupNotice(site)
                        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 14) {
                            GridRow { Text("Project").foregroundStyle(.secondary); Text(site.projectPath).textSelection(.enabled) }
                            GridRow { Text("Document root").foregroundStyle(.secondary); Text(site.documentRoot).textSelection(.enabled) }
                            GridRow { Text("PHP").foregroundStyle(.secondary); Text(runtimeLabel(site)) }
                            GridRow { Text("HTTPS setup").foregroundStyle(.secondary); Text(model.hasSetup(site) ? "Approved for this hostname" : "Setup required") }
                            GridRow { Text("System HTTPS check").foregroundStyle(.secondary); Text(model.runningSiteIDs.contains(site.id) ? "Passed" : "Checked at startup") }
                        }
                        HStack {
                            Button("Open in Browser", systemImage: "globe") { model.open(site) }
                                .disabled(model.isBusy || !model.runningSiteIDs.contains(site.id) || model.environmentState != .running)
                            Button("Reveal in Finder", systemImage: "folder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: site.projectPath)
                            }
                        }
                        Divider()
                        HStack {
                            Button("Edit site") { editingSite = site }
                            Button(site.isEnabled ? "Disable site" : "Enable site") { model.toggleEnabled(site) }
                            Spacer()
                            Button("Remove registration", role: .destructive) { removingSite = site }
                        }.disabled(model.isBusy)
                        Text("Use trusted local projects only. Jerd does not isolate project code from your user account.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(30)
                }
            } else {
                ContentUnavailableView {
                    Label("Add an existing PHP project", systemImage: "folder.badge.plus")
                } description: {
                    Text("Choose a folder, check its hostname, then enable HTTPS. Jerd manages PHP and Caddy.")
                }
            }
        }
        .toolbar {
            if model.isBusy { ProgressView().controlSize(.small) }
            Button("Runtimes", systemImage: "shippingbox") { model.showDashboard(.runtimes) }
            Menu("System setup", systemImage: "lock.shield") {
                Button("Login Items & Extensions") { SMAppService.openSystemSettingsLoginItems() }
                Button("Remove system setup…") { removingSetup = true }
            }.disabled(!model.isLoaded || model.isBusy)
            if !model.isLoaded { Button("Retry load") { model.load() }.disabled(model.isBusy) }
        }
        .sheet(item: $editingSite, onDismiss: { model.presentPreparedSetup() }) { site in SiteEditor(model: model, original: site) }
        .sheet(item: $model.pendingSetup) { setup in HTTPSSetupView(model: model, setup: setup) }
        .alert("Jerd could not complete the operation", isPresented: Binding(
            get: { model.errorMessage != nil && model.pendingSetup == nil && editingSite == nil },
            set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Remove this registration?", isPresented: Binding(
            get: { removingSite != nil }, set: { if !$0 { removingSite = nil } })) {
                Button("Remove registration", role: .destructive) {
                    if let site = removingSite { model.remove(site) }
                    removingSite = nil
                }
            } message: { Text("Jerd will remove this site’s registered host. Other enabled sites will restart. The CA remains trusted while other hosts are registered. The project directory and its files will remain on disk.") }
        .confirmationDialog("Remove Jerd system setup?", isPresented: $removingSetup) {
            Button("Remove system setup", role: .destructive) { model.removeSystemSetup() }
        } message: {
            Text("Jerd will stop the environment, remove its host entries and CA certificate, then unregister its helper. Site records and project files will remain.")
        }
    }

    private func setupNotice(_ site: Site) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 7) {
                Label(!site.isEnabled ? "Disabled" : (model.runningSiteIDs.contains(site.id) ? "Ready" : (model.runningSiteIDs.isEmpty ? model.stateLabel : "Not running")),
                      systemImage: model.runningSiteIDs.contains(site.id) ? "checkmark.circle" : "server.rack").font(.headline)
                if case .failed(let message) = model.environmentState { Text(message).foregroundStyle(.red) }
                Text("All enabled sites run together. Each site uses its selected PHP version.").foregroundStyle(.secondary)
                HStack {
                    if model.runningSiteIDs.contains(site.id) {
                        Button("Stop all sites") { model.stop() }
                    } else if model.hasSetup(site) {
                        Button("Start all sites") { model.start() }.disabled(!site.isEnabled)
                    } else {
                        Button("Enable HTTPS…") { model.prepareHTTPS() }.disabled(!site.isEnabled)
                    }
                    if !model.systemStatus.hostnames.isEmpty {
                        Button("Remove system setup…") { removingSetup = true }
                    }
                }.disabled(model.isBusy)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private func runtimeLabel(_ site: Site) -> String {
        let prefix = site.phpSelection == .followDefault ? "Follow default" : "Pinned"
        if let runtime = try? model.configuration.runtime(for: site) { return "\(prefix): PHP \(runtime.version)" }
        return "\(prefix): runtime unavailable"
    }
}

private struct SiteEditor: View {
    let model: AppModel
    let original: Site
    @Environment(\.dismiss) private var dismiss
    @State private var site: Site
    @State private var confirmed = false
    @State private var suggestion = "Select an existing project directory."
    init(model: AppModel, original: Site) {
        self.model = model
        self.original = original
        _site = State(initialValue: original)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(original.projectPath.isEmpty ? "Add site" : "Edit site").font(.title2.bold())
            Form {
                TextField("Display name", text: $site.displayName)
                TextField("Hostname", text: $site.hostname, prompt: Text("project.test"))
                HStack {
                    TextField("Project", text: $site.projectPath)
                    Button("Choose…") {
                        guard let directory = AppModel.chooseDirectory() else { return }
                        let previousName = URL(fileURLWithPath: site.projectPath).lastPathComponent
                        if site.displayName.isEmpty || site.displayName == previousName { site.displayName = directory.lastPathComponent }
                        if site.hostname.isEmpty || site.hostname == Hostname.suggestion(folderName: previousName) {
                            site.hostname = Hostname.suggestion(folderName: directory.lastPathComponent)
                        }
                        site.projectPath = directory.path
                        suggestRoot()
                    }
                }
                HStack {
                    TextField("Document root", text: $site.documentRoot)
                    Button("Choose…") {
                        if let directory = AppModel.chooseDirectory() { site.documentRoot = directory.path }
                    }
                }
                Button("Inspect project for document root") { suggestRoot() }.disabled(site.projectPath.isEmpty)
                Text(suggestion).font(.callout).foregroundStyle(.secondary)
                Toggle("I confirm that this document root can be served.", isOn: $confirmed)
                Picker("PHP selection", selection: $site.phpSelection) {
                    Text("Follow default").tag(PHPSelection.followDefault)
                    ForEach(model.configuration.runtimes) { runtime in
                        Text("PHP \(runtime.version) — \(runtime.id.uuidString.prefix(6))").tag(PHPSelection.pinned(runtime.id))
                    }
                    if case .pinned(let id) = site.phpSelection, !model.configuration.runtimes.contains(where: { $0.id == id }) {
                        Text("Pinned runtime unavailable").tag(PHPSelection.pinned(id))
                    }
                }
                Toggle("Enabled", isOn: $site.isEnabled)
            }
            .formStyle(.grouped)
            Text("Detection reads files only. It does not execute artisan or project scripts.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save registration") { model.save(site, confirmed: confirmed) { dismiss() } }
                    .keyboardShortcut(.defaultAction).disabled(!confirmed)
            }
        }
        .padding(24).frame(width: 650)
        .disabled(model.isBusy)
        .onChange(of: site.documentRoot) { confirmed = false }
        .onChange(of: site.projectPath) { confirmed = false }
    }

    private func suggestRoot() {
        let path = site.projectPath
        model.perform {
            let result = try await model.registry.suggestRoot(path)
            site.documentRoot = result.path
            suggestion = result.isLaravel ? "Laravel files found. The suggested document root is public." : "Plain PHP project. Select and confirm its document root."
            confirmed = false
        }
    }
}

private struct HTTPSSetupView: View {
    let model: AppModel
    let setup: HTTPSSetup
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Enable HTTPS for \(setup.sites.count) site(s)?").font(.title2.bold())
            ScrollView { Text(setup.request.hostnames.joined(separator: "\n")).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 130)
            Text("Jerd will install its signed helper, map these hostnames to 127.0.0.1, and add its local CA to the system keychain. macOS can ask for administrator approval.")
            Text("macOS will trust this Jerd CA for TLS server certificates, so Safari, Brave, and Chrome can use it. This CA trust applies to all hostnames, not only the sites listed above.")
            Text("Jerd only routes registered .test sites on this Mac. PHP and Caddy run as your user. The helper supplies ports 80 and 443.")
            let removed = Set(model.systemStatus.hostnames).subtracting(setup.request.hostnames).sorted()
            if !removed.isEmpty { Text("This removes HTTPS setup for: " + removed.joined(separator: ", ")) }
            Text("CA SHA-256").font(.headline)
            Text(setup.fingerprint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Text("Use Remove system setup to remove these host entries and the certificate later.").foregroundStyle(.secondary)
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            Button("Open Login Items & Extensions") { SMAppService.openSystemSettingsLoginItems() }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Approve and start") { model.approveHTTPS(setup) }.keyboardShortcut(.defaultAction)
            }
            if model.isBusy { ProgressView("Setting up HTTPS…") }
        }.padding(24).frame(width: 590).disabled(model.isBusy)
    }
}
