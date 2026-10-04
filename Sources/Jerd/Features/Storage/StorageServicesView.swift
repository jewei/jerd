import SwiftUI
import Observation
import JerdCore

@MainActor @Observable
final class StoragePresentation {
    var adding = false
    var settings = false
}

struct StorageServicesView: View {
    @Bindable var presentation: StoragePresentation
    @Bindable var model: StorageModel

    @ViewBuilder var sidebarRows: some View {
        Section("Buckets") {
            ForEach(model.configuration.buckets) { bucket in
                SidebarRow(title: bucket.name, subtitle: bucket.publicRead ? "Public read" : "Private",
                           status: model.bucketStatus(bucket), tone: model.bucketTone(bucket))
                    .tag(WorkspaceSelection.bucket(bucket.name))
            }
        }
    }

    var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Add bucket", systemImage: "plus") { model.errorMessage = nil; presentation.adding = true }
                .disabled(!model.canAdd)
            Divider()
            HStack(spacing: 8) {
                StatusIndicator(title: model.state.title, tone: model.isBusy ? .busy : model.state.tone)
                VStack(alignment: .leading, spacing: 1) {
                    Text("RustFS").font(.callout.weight(.medium))
                    Text(model.state.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                serviceButton.controlSize(.small)
            }
            .accessibilityElement(children: .contain)
        }.padding(12)
    }

    @ViewBuilder var toolbarActions: some View {
        Button("Refresh buckets", systemImage: "arrow.clockwise") { model.refreshBuckets() }
            .help("Refresh buckets")
            .disabled(!model.canChange || model.state != .running)
        Button("Storage settings", systemImage: "gearshape") { model.errorMessage = nil; presentation.settings = true }
            .help("Storage settings")
    }

    var body: some View {
        Group {
            if let bucket = model.selected { detail(bucket) }
            else {
                EmptyPane(title: model.configuration.buckets.isEmpty ? "Local object storage" : "Select a bucket",
                          symbol: "shippingbox",
                          message: model.configuration.runtime == nil ? model.runtimeMessage :
                            model.configuration.buckets.isEmpty ? "Give your application an S3 bucket for uploads and files. Jerd starts RustFS and checks the bucket when you save." :
                            "Select a bucket in the sidebar to view its connection and access settings.") {
                    if model.configuration.runtime == nil {
                        Button("Storage settings", systemImage: "gearshape") { model.errorMessage = nil; presentation.settings = true }
                            .buttonStyle(.borderedProminent)
                    } else if model.configuration.buckets.isEmpty {
                        Button("Add bucket", systemImage: "plus") { model.errorMessage = nil; presentation.adding = true }
                            .primaryAction(model.canAdd)
                    }
                }
            }
        }
        .sheet(isPresented: $presentation.adding) { StorageBucketEditor(model: model) }
        .sheet(isPresented: $presentation.settings) { StorageSettingsView(model: model) }
        .alert("Jerd could not complete the storage operation", isPresented: Binding(
            get: { model.errorMessage != nil && !presentation.adding && !presentation.settings },
            set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }

    @ViewBuilder private var serviceButton: some View {
        if model.processID != nil {
            Button("Stop storage", systemImage: "stop.fill") { model.stop() }.disabled(!model.canChange)
        } else {
            Button("Start storage", systemImage: "play.fill") { model.start() }.disabled(!model.canAdd)
        }
    }

    private func detail(_ bucket: StorageBucket) -> some View {
        GroupedPane(feedback: model.copiedMessage) {
            PaneHeader(bucket.name, subtitle: "S3 bucket · RustFS \(model.configuration.runtime?.version ?? "unavailable")",
                       status: (model.bucketStatus(bucket), model.bucketTone(bucket))) {
                if model.processID == nil {
                    Button("Start storage", systemImage: "play.fill") { model.start() }.primaryAction(model.canAdd)
                } else {
                    serviceButton
                }
                Button("Open console", systemImage: "arrow.up.right.square") { model.openConsole() }
                    .disabled(model.state != .running || model.isShuttingDown)
            }
        } content: {
            if case .failed(let message) = model.state {
                Section { InlineMessage(message) }
            }
            if !bucket.setupComplete {
                Section {
                    HStack(spacing: 12) {
                        InlineMessage("The bucket setup did not finish. Retry to apply its access settings and check it.", kind: .info)
                        Button("Retry setup") { model.retryBucket(bucket) }.disabled(!model.canAdd).fixedSize()
                    }
                }
            } else if model.state == .running, !model.availableBuckets.contains(bucket.name) {
                Section {
                    InlineMessage("This bucket is no longer in RustFS. Its saved settings remain here. Check the console before creating another bucket.", kind: .info)
                }
            }
            Section {
                ValueRow("Endpoint", model.configuration.endpoint.absoluteString, monospaced: true)
                ValueRow("Bucket", bucket.name, monospaced: true)
                ValueRow("Region", model.configuration.region, monospaced: true)
                ValueRow("Addressing", "Path style")
            } header: { Label("Connection", systemImage: "network") } footer: {
                Text("Available only on this Mac. All buckets use the same RustFS service.")
            }
            Section {
                LabeledContent("Bucket access") {
                    Label(bucket.publicRead ? "Public read" : "Private", systemImage: bucket.publicRead ? "eye" : "lock")
                        .foregroundStyle(.secondary)
                }
                ActionRow("Access key", action: "Copy access key", symbol: "key") { model.copy("Access key") }
                    .disabled(!model.canChange)
                ActionRow("Secret key", action: "Copy secret key", symbol: "key") { model.copy("Secret key") }
                    .disabled(!model.canChange)
            } header: { Label("Access", systemImage: "lock.shield") } footer: {
                Text((bucket.publicRead ? "Objects can be read without credentials. Uploads require credentials. " : "Credentials are required to read and write objects. ") +
                     "Use the shared access key and secret key to sign in to the console.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ActionRow(".env settings", action: "Copy Laravel settings", symbol: "doc.on.doc") { model.copy("Laravel settings", bucket: bucket) }
                    .disabled(!model.canChange || !bucket.setupComplete)
            } header: { Text("Laravel") } footer: {
                Text("Laravel needs its S3 filesystem adapter. Copy the settings into your application's .env file, then clear any cached configuration.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                PathRow(label: "Data folder", path: model.paths.data.path) { model.showData() }
                ActionRow("Log", action: "Open log", perform: { model.openLog() })
            } header: { Text("Files") } footer: {
                Text("Buckets, objects, and credentials remain after Stop or Quit.")
            }
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
        SheetScaffold(title: "Add bucket", message: "Jerd starts storage if needed, then creates and checks your bucket.") {
            Section {
                TextField("Bucket name", text: $name, prompt: Text("my-app-uploads"))
                    .focused($nameFocused)
                Toggle("Allow public read access", isOn: $publicRead)
            } footer: {
                Text(publicRead ? "Anyone on this Mac who knows an object URL can read it. Uploads still require credentials." :
                        "This bucket is private. Reading and writing objects requires credentials. Use 3–63 lowercase letters, numbers, dots, or hyphens.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ValueRow("Endpoint", model.configuration.endpoint.absoluteString, monospaced: true)
                ValueRow("Region", model.configuration.region, monospaced: true)
            }
            if let message = localError ?? model.errorMessage { InlineMessage(message) }
        } footer: {
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
        .disabled(model.isBusy || model.isShuttingDown)
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
        SheetScaffold(title: "Storage settings", message: model.runtimeMessage) {
            Section {
                TextField("S3 port", text: $api, prompt: Text("1024–65535"))
                TextField("Console port", text: $console, prompt: Text("1024–65535"))
                ControlRow("Free ports") {
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
                }
            } header: { Text("Ports") } footer: {
                Text(model.processID != nil ? "Stop storage to change ports. Both ports are limited to this Mac. Port changes keep all buckets and objects." :
                        "Both ports are limited to this Mac. Port changes keep all buckets and objects.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .disabled(model.processID != nil)
            Section("Runtime") {
                ControlRow("RustFS", detail: model.configuration.runtime?.version ?? "Unavailable") {
                    Button("Check runtime") { model.load() }.disabled(model.isBusy || model.isShuttingDown)
                    Button("Open log") { model.openLog() }
                }
            }
            if let message = localError ?? model.errorMessage { InlineMessage(message) }
        } footer: {
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
        .disabled(model.isBusy || suggesting)
            .onAppear { api = String(model.configuration.apiPort); console = String(model.configuration.consolePort) }
    }
}
