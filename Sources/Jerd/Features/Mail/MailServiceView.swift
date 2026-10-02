import SwiftUI
import JerdCore

struct MailServiceView: View {
    @Bindable var model: MailModel
    @State private var editing = false

    var body: some View {
        GroupedPane(feedback: model.copiedMessage) {
            PaneHeader("Mail", subtitle: "Capture test emails from your applications and inspect them in one inbox.",
                       status: (model.state.title, model.isBusy ? .busy : model.state.tone)) {
                if model.processID != nil {
                    Button("Stop mail", systemImage: "stop.fill") { model.stop() }.disabled(!model.canChange)
                } else {
                    Button("Start mail", systemImage: "play.fill") { model.start() }
                        .primaryAction(model.canChange && model.configuration.runtime != nil)
                }
                Button("Open inbox", systemImage: "tray") { model.openInbox() }
                    .disabled(model.state != .running || model.isShuttingDown)
                Button("Send test email", systemImage: "paperplane") { model.sendTestEmail() }
                    .disabled(!model.canChange || model.state != .running)
            }
        } content: {
            if case .failed(let message) = model.state {
                Section { InlineMessage(message) }
            }
            if let message = model.testMessage {
                Section { InlineMessage(message, kind: .success) }
            }
            if model.configuration.runtime == nil {
                Section { InlineMessage(model.runtimeMessage, kind: .info) }
            }
            Section {
                ValueRow("Host", "127.0.0.1")
                ValueRow("SMTP port", String(model.configuration.smtpPort))
                ValueRow("Inbox URL", model.configuration.inboxURL.absoluteString)
                ValueRow("Authentication", "No username or password")
                ValueRow("Encryption", "None (local SMTP and HTTP)")
            } header: { Text("Connection") } footer: {
                Text("Both ports are limited to this Mac. External mail delivery is not configured.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Laravel") {
                ActionRow(".env settings", action: "Copy Laravel settings", symbol: "doc.on.doc") { model.copyLaravelSettings() }
                    .disabled(!model.canChange || model.configuration.runtime == nil)
            }
            Section {
                PathRow(label: "Inbox data", path: model.paths.inbox.path) { model.showData() }
                ActionRow("Log", action: "Open log", perform: { model.openLog() })
            } header: { Text("Files") } footer: {
                Text("Messages stay in the inbox after Stop or Quit. Use the inbox to search messages, inspect HTML and attachments, or delete messages.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ControlRow("Mailpit", detail: model.configuration.runtime?.version ?? "Unavailable") {
                    if model.isBusy || model.isShuttingDown { ProgressView().controlSize(.small) }
                    Button("Check runtime") { model.load() }.disabled(model.isBusy || model.isShuttingDown)
                }
                ActionRow("Ports", action: "Edit ports…", perform: { editing = true }) {
                    Text("SMTP \(String(model.configuration.smtpPort)) · Web \(String(model.configuration.webPort))")
                        .foregroundStyle(.secondary)
                }
                .disabled(!model.canChange || model.processID != nil)
            } header: { Text("Service") } footer: {
                if model.processID != nil {
                    Text("Stop mail to change its ports.").font(.callout).foregroundStyle(.secondary)
                }
            }
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
        SheetScaffold(title: "Mail ports",
                      message: "Changing ports keeps the inbox. Update your application's mail settings after a change.") {
            Section {
                TextField("SMTP port", text: $smtp, prompt: Text("1024–65535"))
                TextField("Web port", text: $web, prompt: Text("1024–65535"))
                ControlRow("Free ports") {
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
                }
            } footer: {
                Text("Use two different free ports from 1024 to 65535.").font(.callout).foregroundStyle(.secondary)
            }
            if let message = localError ?? model.errorMessage { InlineMessage(message) }
        } footer: {
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
        .disabled(model.isBusy || suggesting)
        .onAppear { smtp = String(model.configuration.smtpPort); web = String(model.configuration.webPort) }
    }
}
