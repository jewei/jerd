import SwiftUI
import JerdCore

struct MailServiceView: View {
    @Bindable var model: MailModel
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Local mail", systemImage: "tray.full").font(.largeTitle.bold())
                    Text("Capture test emails from your applications and inspect them in one inbox.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.state.title, systemImage: model.state == .running ? "checkmark.circle" : "envelope")
                            .font(.headline)
                        if case .failed(let message) = model.state {
                            Text(message).foregroundStyle(.red).lineLimit(5).textSelection(.enabled)
                        }
                        Text("The mail service runs independently from your sites and databases.")
                            .foregroundStyle(.secondary)
                        HStack {
                            if model.processID != nil {
                                Button("Stop mail") { model.stop() }.disabled(!model.canChange)
                            } else {
                                Button("Start mail") { model.start() }
                                    .disabled(!model.canChange || model.configuration.runtime == nil)
                            }
                            Button("Open inbox", systemImage: "tray") { model.openInbox() }
                                .disabled(model.state != .running || model.isShuttingDown)
                            Button("Send test email", systemImage: "paperplane") { model.sendTestEmail() }
                                .disabled(!model.canChange || model.state != .running)
                        }
                        if let message = model.testMessage { Text(message).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
                    GridRow { Text("Host").foregroundStyle(.secondary); Text("127.0.0.1").textSelection(.enabled) }
                    GridRow { Text("SMTP port").foregroundStyle(.secondary); Text(String(model.configuration.smtpPort)).textSelection(.enabled) }
                    GridRow { Text("Inbox URL").foregroundStyle(.secondary); Text(model.configuration.inboxURL.absoluteString).textSelection(.enabled) }
                    GridRow { Text("Authentication").foregroundStyle(.secondary); Text("No username or password") }
                    GridRow { Text("Encryption").foregroundStyle(.secondary); Text("None (local SMTP and HTTP)") }
                    GridRow { Text("Data folder").foregroundStyle(.secondary); Text(model.paths.inbox.path).font(.callout).textSelection(.enabled) }
                }
                HStack {
                    Button("Copy Laravel settings", systemImage: "doc.on.doc") { model.copyLaravelSettings() }
                        .disabled(!model.canChange || model.configuration.runtime == nil)
                    Button("Show data folder", systemImage: "folder") { model.showData() }
                    Button("Open log", systemImage: "doc.text") { model.openLog() }
                }
                Divider()
                HStack {
                    Button("Edit ports") { editing = true }.disabled(!model.canChange || model.processID != nil)
                    Button("Check runtime") { model.load() }.disabled(model.isBusy || model.isShuttingDown)
                    Spacer()
                    if model.isBusy || model.isShuttingDown { ProgressView().controlSize(.small) }
                    Text(model.configuration.runtime.map { "Mailpit \($0.version)" } ?? "Mailpit unavailable")
                        .foregroundStyle(.secondary)
                }
                if model.configuration.runtime == nil { Text(model.runtimeMessage).foregroundStyle(.secondary).textSelection(.enabled) }
                Text("Both ports are limited to this Mac. Messages stay in the inbox after Stop or Quit. Use the inbox to search messages, inspect HTML and attachments, or delete messages. External mail delivery is not configured.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(30).frame(maxWidth: 1040, alignment: .leading)
        }
        .sheet(isPresented: $editing) { MailPortEditor(model: model) }
        .alert("Jerd could not complete the mail operation", isPresented: Binding(
            get: { model.errorMessage != nil && !editing },
            set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }
}

private struct MailPortEditor: View {
    let model: MailModel
    @Environment(\.dismiss) private var dismiss
    @State private var smtp = ""
    @State private var web = ""
    @State private var localError: String?
    @State private var suggesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Mail ports").font(.title2.bold())
            Form {
                TextField("SMTP port", text: $smtp)
                TextField("Web port", text: $web)
            }
            Text("Use two different free ports from 1024 to 65535. Changing ports keeps the inbox. Update your application's mail settings after a change.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Suggest free ports") {
                suggesting = true
                Task {
                    defer { suggesting = false }
                    do {
                        let ports = try await model.suggestPorts()
                        smtp = String(ports.smtp); web = String(ports.web); localError = nil
                    } catch { localError = error.localizedDescription }
                }
            }
            if let message = localError ?? model.errorMessage { Text(message).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { model.errorMessage = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save ports") {
                    guard let smtpPort = UInt16(smtp), let webPort = UInt16(web), smtpPort > 1023, webPort > 1023, smtpPort != webPort else {
                        localError = "Enter two different ports from 1024 to 65535."
                        return
                    }
                    localError = nil
                    model.edit(smtp: smtpPort, web: webPort) { dismiss() }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 500)
        .disabled(model.isBusy || suggesting)
        .onAppear { smtp = String(model.configuration.smtpPort); web = String(model.configuration.webPort) }
    }
}
