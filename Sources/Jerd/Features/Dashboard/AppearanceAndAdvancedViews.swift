import SwiftUI
import JerdCore

struct AppearanceView: View {
    @Bindable var appearance: AppAppearance
    var body: some View {
        GroupedPane {
            PaneHeader("Appearance", subtitle: "Choose where Jerd appears and which icon it uses.")
        } content: {
            Section {
                Toggle("Show in menu bar", isOn: $appearance.showMenuBar)
                Toggle("Show in Dock", isOn: $appearance.showDock)
            } header: { Text("App visibility") } footer: {
                Text("When both are off, open Jerd from Applications to return to its window.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                    ForEach(AppIconChoice.allCases) { choice in iconButton(choice) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("App icon")
                .padding(.vertical, 6)
            } header: { Text("App icon") } footer: {
                Text("The selected icon appears in the Dock and menu bar while Jerd is open.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func iconButton(_ choice: AppIconChoice) -> some View {
        let selected = appearance.icon == choice
        return Button { appearance.icon = choice } label: {
            VStack(spacing: 6) {
                Group {
                    if let image = appearance.image(for: choice) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 14).fill(.quaternary)
                    }
                }
                .frame(width: 64, height: 64)
                HStack(spacing: 4) {
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    Text(choice.title).font(.callout).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 6)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct AdvancedSettingsView: View {
    let model: AppModel
    @State private var deletingBackup: RetainedBackup?
    @State private var recoveringProcess: ProcessRecoveryFinding?
    @State private var removingRuntime: DevelopmentRuntime?
    var body: some View {
        GroupedPane {
            PaneHeader("Advanced", subtitle: "Recover services, manage backups, and register local executables.") {
                Button("Inspect recovery and backups", systemImage: "magnifyingglass") { model.inspectRecovery() }
            }
        } content: {
            Section { InlineMessage(model.runtimeMessage, kind: .info) }
            if let error = model.errorMessage { Section { InlineMessage(error) } }
            if let status = model.systemStatus.recovery {
                Section("Interrupted HTTPS setup") {
                    Text("\(status.operation) · \(status.phase)").font(.headline)
                    ForEach(status.details, id: \.self) { Text($0) }
                    ValueRow("CA SHA-256", status.fingerprint, monospaced: true)
                    ControlRow("Recovery") {
                        Button("Restore previous setup…") { model.recoverSystemSetup(status, action: .restorePrevious) }
                            .disabled(!status.canRestore)
                        Button("Remove tracked setup…", role: .destructive) { model.recoverSystemSetup(status, action: .removeSetup) }
                            .disabled(!status.canRemove)
                    }
                }
            }
            Section {
                if model.processFindings.isEmpty {
                    Text("No saved services to recover. Select Inspect recovery and backups to check.").foregroundStyle(.secondary)
                }
                ForEach(model.processFindings) { finding in
                    ControlRow(finding.title, detail: finding.detail) {
                        Button(finding.state == .stale ? "Clear stale record…" : "Recover service…") { recoveringProcess = finding }
                            .disabled(!finding.canRecover)
                            .accessibilityLabel("\(finding.state == .stale ? "Clear stale record for" : "Recover") \(finding.title)")
                    }
                }
            } header: { Text("Process recovery") } footer: {
                Text("Inspect services left by a previous Jerd session. Recovery uses a verified process identity and requests a graceful stop.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                if model.retainedBackups.isEmpty {
                    Text("No retained backups. Select Inspect recovery and backups to check.").foregroundStyle(.secondary)
                }
                ForEach(model.retainedBackups) { backup in
                    VStack(alignment: .leading, spacing: 6) {
                        ControlRow("\(backup.service) · \(backup.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Size unavailable")",
                                   detail: backup.detail) {
                            Button("Show backup") { NSWorkspace.shared.open(backup.directory) }
                                .accessibilityLabel("Show \(backup.service) backup")
                            Button("Delete backup…", role: .destructive) { deletingBackup = backup }.disabled(backup.isProtected)
                                .accessibilityLabel("Delete \(backup.service) backup")
                        }
                        Text(backup.directory.path).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(backup.directory.path)
                    }
                }
            } header: { Text("Retained runtime backups") } footer: {
                Text("Runtime updates keep a copy of mail or storage data. Pending recovery protects these copies from deletion.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ControlRow("PHP CLI and FPM") {
                    Button("Select PHP CLI and FPM…") {
                        guard let cli = AppModel.chooseExecutable(message: "Select a trusted PHP CLI executable."),
                              let fpm = AppModel.chooseExecutable(message: "Select the matching PHP-FPM executable.") else { return }
                        model.importPHP(cli: cli, fpm: fpm)
                    }
                }
                ControlRow("Caddy") {
                    Button("Select Caddy…") {
                        if let binary = AppModel.chooseExecutable(message: "Select a trusted Caddy 2 executable.") { model.importCaddy(binary) }
                    }
                }
            } header: { Text("Local executables") } footer: {
                Text("Select trusted executables for development.").font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ForEach(model.configuration.runtimes) { runtime in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            ValueRow("CLI", runtime.cliPath, monospaced: true)
                            ValueRow("FPM", runtime.fpmPath, monospaced: true)
                            ValueRow("Architectures", runtime.architectures.map(\.rawValue).joined(separator: ", "))
                            LabeledContent("CLI extensions") { Text(runtime.cliExtensions.joined(separator: ", ")).textSelection(.enabled) }
                            LabeledContent("FPM extensions") { Text(runtime.fpmExtensions.joined(separator: ", ")).textSelection(.enabled) }
                            HStack {
                                Spacer()
                                Button("Remove registration…", role: .destructive) { removingRuntime = runtime }
                            }
                        }
                        .font(.callout).padding(.vertical, 6)
                    } label: {
                        HStack {
                            Text("PHP \(runtime.version)")
                            Text(runtime.id.uuidString.prefix(6)).font(.callout.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Text("Registered PHP runtimes") } footer: {
                Text("CLI commands use the current site’s PHP selection, or the default outside registered sites.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .disabled(model.isBusy)
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
        .confirmationDialog("Remove this PHP runtime registration?", isPresented: Binding(
            get: { removingRuntime != nil }, set: { if !$0 { removingRuntime = nil } })) {
            Button("Remove registration", role: .destructive) {
                if let runtime = removingRuntime {
                    model.perform { model.configuration = try await model.registry.removeRuntime(runtime.id) }
                }
                removingRuntime = nil
            }
        } message: { Text("Jerd will remove this registration only. The runtime files stay on disk.") }
    }
}
