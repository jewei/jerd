import SwiftUI
import JerdCore

struct DatabaseServicesView: View {
    @Bindable var model: DatabaseModel
    @State private var adding = false
    @State private var editing: DatabaseService?
    @State private var removing: DatabaseService?
    @State private var showRuntimes = false
    @State private var showRetained = false
    @State private var restoring: RetainedDatabase?
    @State private var pendingRestore: RetainedDatabase?

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                ForEach(model.configuration.services) { service in
                    let status = model.status(service)
                    SidebarRow(title: service.name,
                               subtitle: model.runtime(service).map { "\($0.engine.title) \($0.version) · \(String(service.port))" } ?? "Runtime unavailable",
                               status: status.state.title, tone: status.state.tone)
                        .tag(service.id)
                }
            }
            .navigationTitle("Databases")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Add database", systemImage: "plus") { adding = true }
                        .disabled(!canAdd)
                    Spacer()
                }.padding(12)
            }
        } detail: {
            if let service = model.selected, let runtime = model.runtime(service) {
                detail(service, runtime: runtime)
            } else if let service = model.selected {
                ContentUnavailableView {
                    Label("Runtime unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("\(service.name) uses a database runtime that is not installed. Its data folder stays in place.")
                } actions: {
                    Button("Show data folder") { model.revealData(service) }
                    Button("Remove registration…", role: .destructive) { removing = service }
                        .disabled(model.isBusy(service) || model.isSaving)
                }
            } else {
                ContentUnavailableView {
                    Label(model.isLoading ? "Preparing databases" : "No database selected", systemImage: "externaldrive")
                } description: {
                    Text(model.isLoading ? "Checking MySQL, PostgreSQL, and Redis runtimes…" :
                            model.configuration.services.isEmpty ? "Add a MySQL, PostgreSQL, or Redis service. Choose its version and port, then start it." :
                            "Select a database service in the sidebar.")
                } actions: {
                    if !model.isLoading, !model.configuration.runtimes.isEmpty, model.configuration.services.isEmpty {
                        Button("Add database") { adding = true }
                            .primaryAction(canAdd)
                    }
                }
            }
        }
        .toolbar {
            if model.isLoading || model.isShuttingDown { ProgressView().controlSize(.small) }
            Button("Restore registration…", systemImage: "arrow.uturn.backward.circle") { model.inspectRetained(); showRetained = true }
                .help("Restore a removed database registration")
                .disabled(!model.isLoaded || model.isSaving || model.isShuttingDown)
            Button("Database runtimes", systemImage: "gearshape") { showRuntimes = true }
                .help("Database runtimes")
        }
        .sheet(item: $restoring) { item in DatabaseRestoreEditor(model: model, item: item) }
        .sheet(isPresented: $showRetained, onDismiss: { restoring = pendingRestore; pendingRestore = nil }) {
            SheetScaffold(title: "Retained databases",
                          message: "Restore a removed registration with its original runtime and data. Choose a name and an available port.",
                          width: 560) {
                if model.retained.isEmpty {
                    Text(model.isSaving ? "Inspecting data folders…" : "No removed database registrations were found.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.retained) { item in
                    Section {
                        ControlRow(item.name) {
                            Button("Restore…") { pendingRestore = item; showRetained = false }
                                .disabled(!item.canRestore || model.isSaving)
                                .accessibilityLabel("Restore \(item.name)")
                        }
                        if let runtime = item.runtime { ValueRow("Runtime", "\(runtime.engine.title) \(runtime.version)") }
                        if let bytes = item.bytes { ValueRow("Size", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
                        ValueRow("Data folder", item.directory.path)
                        if let problem = item.problem { InlineMessage(problem) }
                    }
                }
                if let error = model.errorMessage { InlineMessage(error) }
            } footer: {
                Button("Inspect again") { model.inspectRetained() }.disabled(model.isSaving)
                if model.isSaving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Done") { model.errorMessage = nil; showRetained = false }.keyboardShortcut(.defaultAction)
            }
            .frame(height: 460)
        }
        .sheet(isPresented: $adding) { DatabaseEditor(model: model, original: nil) }
        .sheet(item: $editing) { service in DatabaseEditor(model: model, original: service) }
        .sheet(isPresented: $showRuntimes) {
            SheetScaffold(title: "Database runtimes", message: model.runtimeMessage, width: 460) {
                Section {
                    if model.configuration.runtimes.isEmpty { Text("No database runtimes are installed.").foregroundStyle(.secondary) }
                    ForEach(model.configuration.runtimes) { runtime in
                        ValueRow(runtime.engine.title, runtime.version)
                    }
                } footer: {
                    Text("A service keeps the version used to create its data. Create a new service to use another version.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } footer: {
                Button("Check runtimes") { model.load() }.disabled(model.isLoading || model.isShuttingDown)
                if model.isLoading { ProgressView().controlSize(.small) }
                Spacer()
                Button("Done") { showRuntimes = false }.keyboardShortcut(.defaultAction)
            }
        }
        .alert("Jerd could not complete the database operation", isPresented: Binding(
            get: { model.errorMessage != nil && !adding && editing == nil && !showRetained && restoring == nil },
            set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Remove this database registration?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("Remove registration", role: .destructive) {
                    if let removing { model.remove(removing) }
                    removing = nil
                }
            } message: {
                Text("Jerd will stop this service and remove its registration. Its database files will remain in the data folder.")
            }
    }

    private var canAdd: Bool {
        model.isLoaded && !model.configuration.runtimes.isEmpty && !model.isLoading && !model.isSaving && !model.isShuttingDown
    }

    private func detail(_ service: DatabaseService, runtime: DatabaseRuntime) -> some View {
        let status = model.status(service)
        let busy = model.isBusy(service)
        let active = status.processID != nil
        return GroupedPane(feedback: model.copiedMessage) {
            PaneHeader(service.name, subtitle: "\(runtime.engine.title) \(runtime.version) · 127.0.0.1:\(String(service.port))",
                       status: (status.state.title, status.state.tone)) {
                if active {
                    Button("Stop service", systemImage: "stop.fill") { model.stop(service) }.disabled(busy)
                } else {
                    Button("Start service", systemImage: "play.fill") { model.start(service) }
                        .primaryAction(!busy)
                }
            }
        } content: {
            if case .failed(let message) = status.state {
                Section { InlineMessage(message) }
            }
            Section {
                ValueRow("Host", "127.0.0.1")
                ValueRow("Port", String(service.port))
                ValueRow("User", runtime.engine.username)
                ValueRow("Database", runtime.engine.database)
                ActionRow("Password", action: "Copy password", symbol: "key") { model.copyConnection(service, passwordOnly: true) }
            } header: { Text("Connection") } footer: {
                Text("Connections are limited to this Mac. A password is created for each service. Quitting Jerd stops its database services.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Laravel") {
                ActionRow(".env settings", action: "Copy Laravel settings", symbol: "doc.on.doc") { model.copyConnection(service) }
            }
            Section("Files") {
                PathRow(label: "Data folder", path: model.paths(service).data.path) { model.revealData(service) }
                ActionRow("Log", action: "Open log", perform: { model.openLog(service) })
            }
            Section {
                ControlRow("Registration") {
                    Button("Edit service…") { editing = service }
                        .disabled(busy || active || model.isSaving)
                    Button("Remove registration…", role: .destructive) { removing = service }
                        .disabled(busy || model.isSaving)
                }
            } footer: {
                Text(active ? "Stop the service to change its name or port. This service runs independently from your sites and other databases." :
                        "This service runs independently from your sites and other databases.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct DatabaseEditor: View {
    let model: DatabaseModel
    let original: DatabaseService?
    @Environment(\.dismiss) private var dismiss
    @State private var engine: DatabaseEngine = .mysql
    @State private var runtimeID = ""
    @State private var name = ""
    @State private var port = ""
    @State private var initialized = false
    @State private var localError: String?

    private var runtimes: [DatabaseRuntime] { model.configuration.runtimes.filter { $0.engine == engine } }
    var body: some View {
        SheetScaffold(title: original == nil ? "Add database service" : "Edit database service",
                      message: original == nil ? "Jerd creates a separate data folder and password. The service listens on 127.0.0.1." :
                        "The service listens on 127.0.0.1. The engine and version stay fixed because the data folder uses them.") {
            Section {
                Picker("Engine", selection: $engine) {
                    ForEach(DatabaseEngine.allCases, id: \.self) { Text($0.title).tag($0) }
                }.disabled(original != nil)
                Picker("Version", selection: $runtimeID) {
                    ForEach(runtimes) { Text($0.version).tag($0.id) }
                }.disabled(original != nil)
                TextField("Name", text: $name)
                TextField("Port", text: $port, prompt: Text("1024–65535"))
            }
            if let error = localError ?? model.errorMessage { InlineMessage(error) }
        } footer: {
            Button("Cancel") { model.errorMessage = nil; dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            if model.isSaving { ProgressView().controlSize(.small) }
            Button(original == nil ? "Create and start" : "Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isSaving || runtimeID.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .disabled(model.isSaving)
        .task {
            guard !initialized else { return }
            if let original, let runtime = model.runtime(original) {
                engine = runtime.engine; runtimeID = runtime.id; name = original.name; port = String(original.port)
            } else { await updateEngine() }
            initialized = true
        }
        .onChange(of: engine) { _, _ in
            if initialized, original == nil { Task { await updateEngine() } }
        }
    }
    private func updateEngine() async {
        let selected = engine
        runtimeID = runtimes.first?.id ?? ""
        name = selected.title
        do {
            let proposed = try await model.suggestPort(selected)
            if engine == selected { port = String(proposed); localError = nil }
        } catch { if engine == selected { localError = error.localizedDescription } }
    }
    private func save() {
        guard let value = UInt16(port), value > 1023 else { localError = "Enter a port from 1024 to 65535."; return }
        localError = nil
        if var original {
            original.name = name.trimmingCharacters(in: .whitespacesAndNewlines); original.port = value
            model.edit(original) { dismiss() }
        } else { model.create(name: name, runtimeID: runtimeID, port: value) { dismiss() } }
    }
}

private struct DatabaseRestoreEditor: View {
    let model: DatabaseModel
    let item: RetainedDatabase
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var port = ""
    @State private var localError: String?
    var body: some View {
        SheetScaffold(title: "Restore database registration",
                      message: "The original runtime and data folder stay in use. Start the service after you restore it.") {
            Section {
                TextField("Name", text: $name)
                TextField("Port", text: $port, prompt: Text("1024–65535"))
            }
            if let error = localError ?? model.errorMessage { InlineMessage(error) }
        } footer: {
            Button("Cancel") { model.errorMessage = nil; dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            if model.isSaving { ProgressView().controlSize(.small) }
            Button("Restore") {
                guard let value = UInt16(port), value > 1023 else { localError = "Enter a port from 1024 to 65535."; return }
                model.restore(item, name: name, port: value) { dismiss() }
            }.keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .disabled(model.isSaving)
            .onAppear { name = item.name; port = String(item.port ?? item.runtime?.engine.defaultPort ?? 3307) }
    }
}
