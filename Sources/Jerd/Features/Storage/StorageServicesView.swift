import SwiftUI
import JerdCore

struct StorageServicesView: View {
    @Bindable var model: StorageModel
    @State private var adding = false
    @State private var settings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedName) {
                ForEach(model.configuration.buckets) { bucket in
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive.fill.badge.icloud")
                            .foregroundStyle(model.bucketStatus(bucket) == "Ready" ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bucket.name).font(.headline)
                            Text(bucket.publicRead ? "Public read" : "Private").font(.caption).foregroundStyle(.secondary)
                            Text(model.bucketStatus(bucket)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 5).tag(bucket.name)
                }
            }
            .navigationTitle("Storage")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Add bucket", systemImage: "plus") { model.errorMessage = nil; adding = true }
                        .disabled(!model.canAdd)
                    Divider()
                    HStack {
                        Label("RustFS · \(model.state.title)", systemImage: "server.rack")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if model.isBusy { ProgressView().controlSize(.small) }
                    }
                    serviceButton
                }.padding()
            }
        } detail: {
            if let bucket = model.selected { detail(bucket) }
            else {
                ContentUnavailableView {
                    Label("Local storage", systemImage: "externaldrive.badge.icloud")
                } description: {
                    Text(model.configuration.runtime == nil ? model.runtimeMessage :
                            "Create an S3 bucket for your application's files. Jerd starts RustFS when you save your first bucket.")
                } actions: {
                    Button("Add bucket") { model.errorMessage = nil; adding = true }
                        .buttonStyle(.borderedProminent).disabled(!model.canAdd)
                }
            }
        }
        .toolbar {
            Button("Refresh buckets", systemImage: "arrow.clockwise") { model.refreshBuckets() }
                .disabled(!model.canChange || model.state != .running)
            Button("Storage settings", systemImage: "gearshape") { model.errorMessage = nil; settings = true }
        }
        .sheet(isPresented: $adding) { StorageBucketEditor(model: model) }
        .sheet(isPresented: $settings) { StorageSettingsView(model: model) }
        .alert("Jerd could not complete the storage operation", isPresented: Binding(
            get: { model.errorMessage != nil && !adding && !settings },
            set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }

    @ViewBuilder private var serviceButton: some View {
        if model.processID != nil {
            Button("Stop storage") { model.stop() }.disabled(!model.canChange)
        } else {
            Button("Start storage") { model.start() }.disabled(!model.canAdd)
        }
    }
    private func detail(_ bucket: StorageBucket) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bucket.name).font(.largeTitle.bold()).textSelection(.enabled)
                    Text("S3 bucket · RustFS \(model.configuration.runtime?.version ?? "")")
                        .font(.title3).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.bucketStatus(bucket), systemImage: model.bucketStatus(bucket) == "Ready" ? "checkmark.circle" : "externaldrive")
                            .font(.headline)
                        if case .failed(let message) = model.state { Text(message).foregroundStyle(.red).textSelection(.enabled) }
                        if !bucket.setupComplete {
                            Text("The bucket setup did not finish. Retry to apply its access settings and check it.").foregroundStyle(.secondary)
                            Button("Retry setup") { model.retryBucket(bucket) }.disabled(!model.canAdd)
                        } else if model.state == .running, !model.availableBuckets.contains(bucket.name) {
                            Text("This bucket is no longer in RustFS. Its saved settings remain here. Check the console before creating another bucket.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(bucket.publicRead ? "Objects can be read without credentials. Uploads require credentials." :
                                    "Credentials are required to read and write objects.").foregroundStyle(.secondary)
                        }
                        HStack {
                            serviceButton
                            Button("Open console", systemImage: "arrow.up.right.square") { model.openConsole() }
                                .disabled(model.state != .running || model.isShuttingDown)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
                    GridRow { Text("Endpoint").foregroundStyle(.secondary); Text(model.configuration.endpoint.absoluteString).textSelection(.enabled) }
                    GridRow { Text("Bucket").foregroundStyle(.secondary); Text(bucket.name).textSelection(.enabled) }
                    GridRow { Text("Region").foregroundStyle(.secondary); Text(model.configuration.region).textSelection(.enabled) }
                    GridRow { Text("Access").foregroundStyle(.secondary); Text(bucket.publicRead ? "Public read (this Mac only)" : "Private") }
                    GridRow { Text("Addressing").foregroundStyle(.secondary); Text("Path style") }
                    GridRow { Text("Access key").foregroundStyle(.secondary); Button("Copy access key") { model.copy("Access key") }.disabled(!model.canChange) }
                    GridRow { Text("Secret key").foregroundStyle(.secondary); Button("Copy secret key") { model.copy("Secret key") }.disabled(!model.canChange) }
                }
                HStack {
                    Button("Copy Laravel settings", systemImage: "doc.on.doc") { model.copy("Laravel settings", bucket: bucket) }
                        .disabled(!model.canChange || !bucket.setupComplete)
                    Button("Show data folder", systemImage: "folder") { model.showData() }
                    Button("Open log", systemImage: "doc.text") { model.openLog() }
                }
                if let copied = model.copiedMessage { Text(copied).font(.callout).foregroundStyle(.secondary) }
                Divider()
                Text("All local buckets share one RustFS service and its credentials. Use the access key and secret key to sign in to the console. Buckets and objects remain after Stop or Quit.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Laravel needs its S3 filesystem adapter. Copy the settings into your application's .env file, then clear any cached configuration.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(30)
        }
    }
}

private struct StorageBucketEditor: View {
    let model: StorageModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var publicRead = false
    @State private var localError: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add bucket").font(.title2.bold())
            Text("Save a bucket and start using S3 storage in your application.").foregroundStyle(.secondary)
            Form {
                TextField("Bucket name", text: $name, prompt: Text("my-app-uploads"))
                    .focused($nameFocused)
                Toggle("Allow public read access", isOn: $publicRead)
            }
            Text(publicRead ? "Anyone on this Mac who knows an object URL can read it. Uploads still require credentials." :
                    "This bucket is private. Reading and writing objects requires credentials.")
                .font(.callout).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow { Text("Endpoint").foregroundStyle(.secondary); Text(model.configuration.endpoint.absoluteString) }
                GridRow { Text("Region").foregroundStyle(.secondary); Text(model.configuration.region) }
            }
            Text("Jerd creates the credentials and starts storage if needed. Your bucket is ready when Save finishes.")
                .font(.callout).foregroundStyle(.secondary)
            if let message = localError ?? model.errorMessage { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel") { model.errorMessage = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small); Text("Preparing bucket…").foregroundStyle(.secondary) }
                Button("Save") {
                    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    do { try StorageBucket.validateName(value) }
                    catch { localError = error.localizedDescription; return }
                    localError = nil
                    model.addBucket(name: value, publicRead: publicRead) { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(name.isEmpty)
            }
        }.padding(24).frame(width: 520).disabled(model.isBusy || model.isShuttingDown)
            .interactiveDismissDisabled(model.isBusy)
            .onAppear { nameFocused = true }
    }
}

private struct StorageSettingsView: View {
    let model: StorageModel
    @Environment(\.dismiss) private var dismiss
    @State private var api = ""
    @State private var console = ""
    @State private var localError: String?
    @State private var suggesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Storage settings").font(.title2.bold())
            Text(model.runtimeMessage).foregroundStyle(.secondary)
            Form {
                TextField("S3 port", text: $api)
                TextField("Console port", text: $console)
            }.disabled(model.processID != nil)
            Text("Stop storage to change ports. Both ports are limited to this Mac. Port changes keep all buckets and objects.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Suggest free ports") {
                    suggesting = true
                    Task {
                        defer { suggesting = false }
                        do {
                            let ports = try await model.suggestPorts()
                            api = String(ports.api); console = String(ports.console); localError = nil
                        } catch { localError = error.localizedDescription }
                    }
                }.disabled(model.processID != nil || !model.canChange)
                Button("Check runtime") { model.load() }.disabled(model.isBusy || model.isShuttingDown)
                Button("Open log") { model.openLog() }
            }
            if let message = localError ?? model.errorMessage { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Done") { model.errorMessage = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save ports") {
                    guard let apiPort = UInt16(api), let consolePort = UInt16(console), apiPort > 1023, consolePort > 1023, apiPort != consolePort else {
                        localError = "Enter two different ports from 1024 to 65535."; return
                    }
                    localError = nil
                    model.edit(api: apiPort, console: consolePort) { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(model.processID != nil || !model.canChange)
            }
        }.padding(24).frame(width: 520).disabled(model.isBusy || suggesting)
            .onAppear { api = String(model.configuration.apiPort); console = String(model.configuration.consolePort) }
    }
}
