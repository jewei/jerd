import SwiftUI
import JerdCore

struct AppearanceView: View {
    @Bindable var appearance: AppAppearance
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Appearance").font(.largeTitle.bold())
                    Text("Choose where Jerd appears and which icon it uses.").foregroundStyle(.secondary)
                }
                GroupBox("App visibility") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Show in menu bar", isOn: $appearance.showMenuBar)
                        Toggle("Show in Dock", isOn: $appearance.showDock)
                        Text("When both are off, open Jerd from Applications to return to its window.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                GroupBox("App icon") {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                            ForEach(AppIconChoice.allCases) { choice in
                                Button { appearance.icon = choice } label: {
                                    VStack(spacing: 6) {
                                        if let image = appearance.image(for: choice) {
                                            Image(nsImage: image).resizable().scaledToFit().frame(width: 70, height: 70)
                                        }
                                        Text(choice.title).font(.caption)
                                        Image(systemName: appearance.icon == choice ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(appearance.icon == choice ? Color.accentColor : Color.secondary)
                                    }.frame(maxWidth: .infinity).padding(8)
                                        .background(appearance.icon == choice ? Color.accentColor.opacity(0.10) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(choice.title)
                                    .accessibilityValue(appearance.icon == choice ? "Selected" : "Not selected")
                            }
                        }.padding(.vertical, 8)
                        Text("The selected icon appears in the Dock and menu bar while Jerd is open.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(12)
                }
            }.frame(maxWidth: 900, alignment: .leading).padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct AdvancedSettingsView: View {
    let model: AppModel
    @State private var deletingBackup: RetainedBackup?
    @State private var recoveringProcess: ProcessRecoveryFinding?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Advanced").font(.largeTitle.bold())
                Text(model.runtimeMessage).foregroundStyle(.secondary)
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                recoveryControls
                GroupBox("Local executables") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select trusted executables for development.")
                        Button("Select PHP CLI and FPM…") {
                            guard let cli = AppModel.chooseExecutable(message: "Select a trusted PHP CLI executable."),
                                  let fpm = AppModel.chooseExecutable(message: "Select the matching PHP-FPM executable.") else { return }
                            model.importPHP(cli: cli, fpm: fpm)
                        }
                        Button("Select Caddy…") {
                            if let binary = AppModel.chooseExecutable(message: "Select a trusted Caddy 2 executable.") { model.importCaddy(binary) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                ForEach(model.configuration.runtimes) { runtime in
                    DisclosureGroup("PHP \(runtime.version) · \(runtime.id.uuidString.prefix(6))") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CLI: \(runtime.cliPath)")
                            Text("FPM: \(runtime.fpmPath)")
                            Text("Architectures: \(runtime.architectures.map(\.rawValue).joined(separator: ", "))")
                            Text("CLI extensions: \(runtime.cliExtensions.joined(separator: ", "))")
                            Text("FPM extensions: \(runtime.fpmExtensions.joined(separator: ", "))")
                            Button("Remove registration", role: .destructive) {
                                model.perform { model.configuration = try await model.registry.removeRuntime(runtime.id) }
                            }
                        }.font(.callout).textSelection(.enabled).padding(.vertical, 10)
                    }
                }
                Text("CLI commands use the current site’s PHP selection, or the default outside registered sites.")
                    .foregroundStyle(.secondary)
            }.frame(maxWidth: 1000, alignment: .leading).padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
        }.disabled(model.isBusy)
        .confirmationDialog("Delete this retained backup?", isPresented: Binding(
            get: { deletingBackup != nil }, set: { if !$0 { deletingBackup = nil } })) {
            Button("Delete backup", role: .destructive) {
                if let backup = deletingBackup { model.removeBackup(backup.id) }
                deletingBackup = nil
            }
        } message: { Text("This removes only the selected backup. It cannot be undone. Current service data stays in place.") }
        .confirmationDialog("Recover this saved service?", isPresented: Binding(
            get: { recoveringProcess != nil }, set: { if !$0 { recoveringProcess = nil } })) {
            Button("Recover service") {
                if let finding = recoveringProcess { model.recoverProcess(finding.id) }
                recoveringProcess = nil
            }
        } message: { Text(recoveringProcess?.detail ?? "") }
    }

    private var recoveryControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("Inspect recovery and retained backups") { model.inspectRecovery() }
            if let status = model.systemStatus.recovery {
                GroupBox("Interrupted HTTPS setup") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(status.operation) · \(status.phase)").font(.headline)
                        ForEach(status.details, id: \.self) { Text($0) }
                        Text("CA SHA-256: \(status.fingerprint)").font(.caption).textSelection(.enabled)
                        HStack {
                            Button("Restore previous setup…") { model.recoverSystemSetup(status, action: .restorePrevious) }
                                .disabled(!status.canRestore)
                            Button("Remove tracked setup…", role: .destructive) { model.recoverSystemSetup(status, action: .removeSetup) }
                                .disabled(!status.canRemove)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
            }
            GroupBox("Process recovery") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inspect services left by a previous Jerd session. Recovery uses a verified process identity and requests a graceful stop.").foregroundStyle(.secondary)
                    ForEach(model.processFindings) { finding in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(finding.title).font(.headline)
                            Text(finding.detail).font(.callout).textSelection(.enabled)
                            Button(finding.state == .stale ? "Clear stale record…" : "Recover service…") { recoveringProcess = finding }
                                .disabled(!finding.canRecover)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            GroupBox("Retained runtime backups") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Runtime updates keep a copy of mail or storage data. Pending recovery protects these copies from deletion.").foregroundStyle(.secondary)
                    ForEach(model.retainedBackups) { backup in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(backup.service) · \(backup.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Size unavailable")").font(.headline)
                            Text(backup.directory.path).font(.caption).textSelection(.enabled)
                            Text(backup.detail).font(.callout)
                            HStack {
                                Button("Show backup") { NSWorkspace.shared.open(backup.directory) }
                                Button("Delete backup…", role: .destructive) { deletingBackup = backup }.disabled(backup.isProtected)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
        }
    }
}
