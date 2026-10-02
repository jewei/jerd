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
                    let status = siteStatus(site)
                    SidebarRow(title: site.displayName, subtitle: site.hostname,
                               status: status.title, tone: status.tone, dimmed: !site.isEnabled)
                        .tag(site.id)
                }
            }
            .navigationTitle("Sites")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Add site", systemImage: "plus") { addSite() }
                        .disabled(!model.isLoaded || model.isBusy)
                    Spacer()
                }.padding(12)
            }
        } detail: {
            if let site = model.selectedSite {
                detail(site)
            } else {
                ContentUnavailableView {
                    Label(model.configuration.sites.isEmpty ? "Add an existing PHP project" : "No site selected",
                          systemImage: "folder.badge.plus")
                } description: {
                    Text(model.configuration.sites.isEmpty ? "Choose a folder, check its hostname, then enable HTTPS. Jerd manages PHP and Caddy." :
                            "Select a site in the sidebar.")
                } actions: {
                    if model.configuration.sites.isEmpty {
                        Button("Add site") { addSite() }
                            .primaryAction(model.isLoaded && !model.isBusy)
                    }
                }
            }
        }
        .toolbar {
            if model.isBusy { ProgressView().controlSize(.small) }
            if !model.isLoaded {
                Button("Retry load", systemImage: "arrow.clockwise") { model.load() }
                    .help("Retry loading sites").disabled(model.isBusy)
            }
            Button("Runtimes", systemImage: "shippingbox") { model.showDashboard(.runtimes) }
                .help("Manage runtimes")
            Menu("System setup", systemImage: "lock.shield") {
                Button("Login Items & Extensions") { SMAppService.openSystemSettingsLoginItems() }
                Button("Remove system setup…") { removingSetup = true }
            }
            .help("System setup")
            .disabled(!model.isLoaded || model.isBusy)
        }
        .sheet(item: $editingSite, onDismiss: { model.presentPreparedSetup() }) { site in SiteEditor(model: model, original: site) }
        .sheet(item: $model.pendingSetup, onDismiss: { model.discardPreparedSetup() }) { setup in HTTPSSetupView(model: model, setup: setup) }
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

    private func addSite() {
        editingSite = Site(displayName: "", projectPath: "", documentRoot: "", hostname: "")
    }

    private func siteStatus(_ site: Site) -> (title: String, tone: StatusTone) {
        if !site.isEnabled { return ("Disabled", .idle) }
        if model.runningSiteIDs.contains(site.id) { return ("Ready", .ready) }
        if !model.runningSiteIDs.isEmpty { return ("Not running", .idle) }
        if model.isBusy, model.environmentState != .running { return (model.stateLabel, .busy) }
        return (model.stateLabel, model.environmentState.tone)
    }

    private func detail(_ site: Site) -> some View {
        let running = model.runningSiteIDs.contains(site.id)
        let status = siteStatus(site)
        return GroupedPane {
            PaneHeader(site.displayName, subtitle: "https://\(site.hostname)", status: status) {
                Button("Open in browser", systemImage: "safari") { model.open(site) }
                    .primaryAction(!model.isBusy && running && model.environmentState == .running)
                Button("Edit site…") { editingSite = site }.disabled(model.isBusy)
            }
        } content: {
            if case .failed(let message) = model.environmentState {
                Section { InlineMessage(message) }
            }
            Section {
                ControlRow("Environment") {
                    StatusBadge(title: model.stateLabel, tone: model.isBusy ? .busy : model.environmentState.tone)
                    environmentActions(site)
                }
                if let message = model.operationMessage { InlineMessage(message, kind: .info) }
            } header: { Text("All sites") } footer: {
                Text((site.isEnabled ? "" : "Enable this site to start it or set up HTTPS. ") +
                     "These controls apply to every enabled site. Ready means PHP-FPM and HTTPS passed their checks. Project code is not checked.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Site") {
                PathRow(label: "Project", path: site.projectPath) {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: site.projectPath)
                }
                ValueRow("Document root", site.documentRoot)
                ValueRow("PHP", runtimeLabel(site))
            }
            Section("Checks") {
                ValueRow("HTTPS setup", model.hasSetup(site) ? "Approved for this hostname" : "Setup required")
                ValueRow("PHP-FPM check", running ? "Private ping passed" : "Checked at startup")
                ValueRow("System HTTPS check", running ? "Passed" : "Checked at startup")
            }
            Section {
                ControlRow("Registration") {
                    Button(site.isEnabled ? "Disable site" : "Enable site") { model.toggleEnabled(site) }
                    Button("Remove registration…", role: .destructive) { removingSite = site }
                }
                .disabled(model.isBusy)
            } footer: {
                Text("Removing a registration keeps the project folder. Use trusted local projects only. Jerd does not isolate project code from your user account.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func environmentActions(_ site: Site) -> some View {
        if !model.runningSiteIDs.isEmpty || model.isBusy {
            Button("Stop all sites") { model.stop() }.disabled(!model.canStop)
        } else if model.hasSetup(site) {
            Button("Start all sites") { model.start() }.disabled(!site.isEnabled || model.isBusy)
        } else {
            Button("Enable HTTPS…") { model.prepareHTTPS() }.disabled(!site.isEnabled || model.isBusy)
        }
        if !model.systemStatus.hostnames.isEmpty {
            Button("Remove system setup…") { removingSetup = true }.disabled(model.isBusy)
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
    @State private var suggestion: String
    init(model: AppModel, original: Site) {
        self.model = model
        self.original = original
        _site = State(initialValue: original)
        _suggestion = State(initialValue: original.projectPath.isEmpty ? "Select an existing project directory." :
            "Inspect the project to suggest its document root.")
    }
    var body: some View {
        SheetScaffold(title: original.projectPath.isEmpty ? "Add site" : "Edit site",
                      message: "Detection reads files only. It does not execute artisan or project scripts.", width: 620) {
            Section("Project") {
                HStack {
                    TextField("Project folder", text: $site.projectPath, prompt: Text("/path/to/project"))
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
                    .accessibilityLabel("Choose project folder")
                }
                TextField("Display name", text: $site.displayName)
                TextField("Hostname", text: $site.hostname, prompt: Text("project.test"))
            }
            .disabled(model.isBusy)
            Section {
                HStack {
                    TextField("Document root", text: $site.documentRoot)
                    Button("Choose…") {
                        if let directory = AppModel.chooseDirectory() { site.documentRoot = directory.path }
                    }
                    .accessibilityLabel("Choose document root")
                }
                HStack(spacing: 12) {
                    Text(suggestion).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("Inspect project") { suggestRoot() }.disabled(site.projectPath.isEmpty).fixedSize()
                }
                Toggle("I confirm that this document root can be served.", isOn: $confirmed)
            } header: { Text("Document root") } footer: {
                if !confirmed {
                    Text("Confirm the document root to save. Changing the folder or document root clears the confirmation.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .disabled(model.isBusy)
            Section("Runtime") {
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
            .disabled(model.isBusy)
            if let error = model.errorMessage { InlineMessage(error) }
        } footer: {
            Button(model.isBusy ? "Cancel operation and stop sites" : "Cancel") {
                if model.isBusy { model.stop() } else { dismiss() }
            }.keyboardShortcut(.cancelAction).disabled(model.stopInProgress)
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button("Save registration") { model.save(site, confirmed: confirmed) { dismiss() } }
                .keyboardShortcut(.defaultAction).disabled(!confirmed || model.isBusy)
        }
        .frame(height: 560)
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
        let count = setup.sites.count
        let removed = Set(model.systemStatus.hostnames).subtracting(setup.request.hostnames).sorted()
        SheetScaffold(title: "Enable HTTPS for \(count) \(count == 1 ? "site" : "sites")?",
                      message: "macOS can ask for administrator approval.", width: 600) {
            Section("Hostnames") {
                ForEach(setup.request.hostnames, id: \.self) { Text($0).textSelection(.enabled) }
            }
            if !removed.isEmpty {
                Section("Setup removed for") {
                    ForEach(removed, id: \.self) { Text($0).textSelection(.enabled) }
                }
            }
            Section("Changes") {
                Label("Jerd installs its signed helper, maps these hostnames to 127.0.0.1, and adds its local CA to the system keychain.",
                      systemImage: "lock.shield")
                Label("macOS will trust this Jerd CA for TLS server certificates, so Safari, Brave, and Chrome can use it. This CA trust applies to all hostnames, not only the sites listed above.",
                      systemImage: "exclamationmark.shield")
                Label("Jerd only routes registered .test sites on this Mac. PHP and Caddy run as your user. The helper supplies ports 80 and 443.",
                      systemImage: "network")
            }
            Section {
                Text(setup.fingerprint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            } header: { Text("CA SHA-256") } footer: {
                Text("Use Remove system setup to remove these host entries and the certificate later.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ControlRow("Helper approval") {
                    Button("Open Login Items & Extensions") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            if let error = model.errorMessage { InlineMessage(error) }
        } footer: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
                Text(model.operationMessage ?? "Setting up HTTPS…").foregroundStyle(.secondary).lineLimit(1)
            }
            Button("Approve and start") { model.approveHTTPS(setup) }.keyboardShortcut(.defaultAction)
        }
        .frame(height: 600)
        .disabled(model.isBusy)
    }
}
