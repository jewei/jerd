import SwiftUI
import JerdCore

struct DatabaseServicesView: View {
    @Bindable var model: DatabaseModel
    @State private var adding = false
    @State private var editing: DatabaseService?
    @State private var removing: DatabaseService?
    @State private var showRuntimes = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                ForEach(model.configuration.services) { service in
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(model.status(service).state == .running ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(service.name).font(.headline)
                            if let runtime = model.runtime(service) {
                                Text("\(runtime.engine.title) \(runtime.version) · \(service.port)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(model.status(service).state.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 5).tag(service.id)
                }
            }
            .navigationTitle("Databases")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Add database", systemImage: "plus") { adding = true }
                        .disabled(!model.isLoaded || model.configuration.runtimes.isEmpty || model.isLoading || model.isSaving || model.isShuttingDown)
                    Spacer()
                }.padding()
            }
        } detail: {
            if let service = model.selected, let runtime = model.runtime(service) {
                detail(service, runtime: runtime)
            } else {
                ContentUnavailableView {
                    Label("Local databases", systemImage: "externaldrive")
                } description: {
                    Text(model.isLoading ? "Preparing MySQL, PostgreSQL, and Redis…" : "Add a database service, choose its version and port, then start it.")
                } actions: {
                    if !model.isLoading, !model.configuration.runtimes.isEmpty {
                        Button("Add database") { adding = true }.disabled(model.isSaving || model.isShuttingDown)
                    }
                }
            }
        }
        .toolbar {
            if model.isLoading || model.isShuttingDown { ProgressView().controlSize(.small) }
            Button("Database runtimes", systemImage: "gearshape") { showRuntimes = true }
        }
        .sheet(isPresented: $adding) { DatabaseEditor(model: model, original: nil) }
        .sheet(item: $editing) { service in DatabaseEditor(model: model, original: service) }
        .sheet(isPresented: $showRuntimes) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Database runtimes").font(.title2.bold())
                Text(model.runtimeMessage).foregroundStyle(.secondary)
                ForEach(model.configuration.runtimes) { runtime in
                    HStack {
                        Text(runtime.engine.title).font(.headline)
                        Spacer()
                        Text(runtime.version).monospacedDigit()
                    }
                }
                Text("A service keeps the version used to create its data. Create a new service to use another version.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Check runtimes") { model.load() }.disabled(model.isLoading || model.isShuttingDown)
                    Spacer()
                    Button("Done") { showRuntimes = false }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 500)
        }
        .alert("Jerd could not complete the database operation", isPresented: Binding(
            get: { model.errorMessage != nil && !adding && editing == nil },
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

    private func detail(_ service: DatabaseService, runtime: DatabaseRuntime) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(service.name).font(.largeTitle.bold())
                    Text("\(runtime.engine.title) \(runtime.version)").font(.title3).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.status(service).state.title,
                              systemImage: model.status(service).state == .running ? "checkmark.circle" : "externaldrive")
                            .font(.headline)
                        if case .failed(let message) = model.status(service).state {
                            Text(message).foregroundStyle(.red).lineLimit(5).textSelection(.enabled)
                        }
                        Text("This service runs independently from your sites and other databases.").foregroundStyle(.secondary)
                        if model.status(service).processID != nil {
                            Button("Stop service") { model.stop(service) }.disabled(model.isBusy(service))
                        } else {
                            Button("Start service") { model.start(service) }.disabled(model.isBusy(service))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 14) {
                    GridRow { Text("Host").foregroundStyle(.secondary); Text("127.0.0.1").textSelection(.enabled) }
                    GridRow { Text("Port").foregroundStyle(.secondary); Text(String(service.port)).textSelection(.enabled) }
                    GridRow { Text("User").foregroundStyle(.secondary); Text(runtime.engine.username).textSelection(.enabled) }
                    GridRow { Text("Database").foregroundStyle(.secondary); Text(runtime.engine.database).textSelection(.enabled) }
                    GridRow {
                        Text("Password").foregroundStyle(.secondary)
                        Button("Copy password") { model.copyConnection(service, passwordOnly: true) }
                    }
                    GridRow {
                        Text("Data folder").foregroundStyle(.secondary)
                        Text(model.paths(service).data.path).font(.callout).textSelection(.enabled)
                    }
                }
                HStack {
                    Button("Copy Laravel settings", systemImage: "doc.on.doc") { model.copyConnection(service) }
                    Button("Show data folder", systemImage: "folder") { model.revealData(service) }
                    Button("Open log", systemImage: "doc.text") { model.openLog(service) }
                }
                Divider()
                HStack {
                    Button("Edit service") { editing = service }
                        .disabled(model.isBusy(service) || model.status(service).processID != nil || model.isSaving)
                    Spacer()
                    Button("Remove registration", role: .destructive) { removing = service }
                        .disabled(model.isBusy(service) || model.isSaving)
                }
                Text("Connections are limited to this Mac. A password is created for each service. Quitting Jerd stops its database services.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(30)
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
        VStack(alignment: .leading, spacing: 18) {
            Text(original == nil ? "Add database service" : "Edit database service").font(.title2.bold())
            Form {
                Picker("Engine", selection: $engine) {
                    ForEach(DatabaseEngine.allCases, id: \.self) { Text($0.title).tag($0) }
                }.disabled(original != nil || model.isSaving)
                Picker("Version", selection: $runtimeID) {
                    ForEach(runtimes) { Text($0.version).tag($0.id) }
                }.disabled(original != nil || model.isSaving)
                TextField("Name", text: $name)
                TextField("Port", text: $port)
            }.disabled(model.isSaving)
            Text("Jerd will create a separate data folder and password. The service will listen on 127.0.0.1.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = localError ?? model.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel") { model.errorMessage = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.isSaving { ProgressView().controlSize(.small) }
                Button(original == nil ? "Create and start" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isSaving || runtimeID.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.disabled(model.isSaving)
        }
        .padding(24).frame(width: 500)
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
