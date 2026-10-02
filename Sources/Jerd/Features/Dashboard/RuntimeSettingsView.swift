import SwiftUI
import JerdCore

struct RuntimeSettingsView: View {
    let model: AppModel
    private var updates: RuntimeUpdatesModel { model.updates }
    var body: some View {
        GroupedPane {
            PaneHeader("Runtimes", subtitle: "Choose a version, then install it. PHP versions remain available for sites that use them.") {
                if updates.isChecking { ProgressView().controlSize(.small) }
                Button("Check for runtime updates", systemImage: "arrow.clockwise") { updates.check(model: model) }
                    .disabled(updates.isChecking || updates.isShuttingDown)
            }
        } content: {
            if let error = updates.loadError { Section { InlineMessage(error) } }
            if let error = model.errorMessage { Section { InlineMessage(error) } }
            ForEach(RuntimeKind.allCases) { kind in runtimeSection(kind) }
        }
    }

    private func runtimeSection(_ kind: RuntimeKind) -> some View {
        let versions = updates.installedVersions(kind, model: model)
        let check = updates.checks[kind]
        return Section {
            if kind == .php, !model.configuration.runtimes.isEmpty {
                phpSelections
            } else {
                LabeledContent("Installed") {
                    Text(versions.isEmpty ? "Unavailable" : versions.joined(separator: ", "))
                        .textSelection(.enabled).id(versions)
                }
            }
            if let check {
                if let error = check.error { InlineMessage(error) }
                if !check.releases.isEmpty {
                    ControlRow("Available") {
                        HStack(spacing: 10) {
                            Picker("Available", selection: Binding(get: { updates.selections[kind] ?? "" }, set: { updates.selections[kind] = $0 })) {
                                ForEach(check.releases) { release in
                                    Text(release.versionLabel + (updates.isInstalled(release, model: model) ? " · Installed" : "")).tag(release.id)
                                }
                            }.labelsHidden().accessibilityLabel("\(kind.title) version").frame(maxWidth: 260)
                            if let release = updates.selectedRelease(kind) { installControl(release) }
                        }
                    }
                    if let release = updates.selectedRelease(kind) {
                        ControlRow("Release", detail: release.sha256.map { "Package build \($0.prefix(12))" } ??
                                   "Install verifies this package again. Its source does not provide a build digest before download.") {
                            Link("Release source", destination: release.source)
                        }
                    }
                }
            }
            if updates.installing == kind, let progress = updates.progress {
                HStack {
                    if let fraction = progress.fraction { ProgressView(value: fraction).frame(width: 120) }
                    else { ProgressView().controlSize(.small) }
                    Text(progress.message).font(.callout)
                    Spacer()
                    if updates.canCancel { Button("Cancel") { updates.cancelInstall() } }
                }
            }
            if let message = updates.messages[kind] { InlineMessage(message, kind: .info) }
            if let error = updates.errors[kind] { InlineMessage(error) }
        } header: {
            Text(kind.title)
        } footer: {
            Text(footer(kind, checked: check?.checkedAt)).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func footer(_ kind: RuntimeKind, checked: Date?) -> String {
        var parts = [checked.map { "Checked \($0.formatted(date: .abbreviated, time: .shortened))." } ?? "Updates have not been checked."]
        switch kind {
        case .mysql: parts.append("MySQL uses the 8.4 LTS series.")
        case .postgresql: parts.append("PostgreSQL uses the 18 series from Postgres.app.")
        case .redis: parts.append("Redis builds need the Xcode command line tools.")
        case .mailpit, .rustfs: parts.append("An update restarts this service. Jerd keeps a local data backup for recovery.")
        default: break
        }
        return parts.joined(separator: " ")
    }
    @ViewBuilder private var phpSelections: some View {
        ForEach(model.configuration.runtimes) { runtime in
            ControlRow("PHP \(runtime.version)",
                       detail: updates.installed.first(where: { $0.executable.path == runtime.cliPath }).map { "Build \($0.archiveSHA256.prefix(12))" }) {
                if model.configuration.defaultRuntimeID == runtime.id {
                    Text("Default").foregroundStyle(.secondary)
                } else {
                    Button("Use as default") { model.setDefaultRuntime(runtime.id) }
                        .disabled(model.isBusy || updates.installing != nil)
                        .accessibilityLabel("Use PHP \(runtime.version) as default")
                }
            }
        }
    }
    @ViewBuilder private func installControl(_ release: RuntimeRelease) -> some View {
        if updates.isInstalled(release, model: model) {
            Label("Installed", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
        } else if release.kind == .php {
            HStack {
                Button("Install and use") { updates.install(release, model: model) }
                Menu {
                    Button("Install only") { updates.install(release, model: model, useAsDefault: false) }
                } label: { Image(systemName: "chevron.down") }.menuStyle(.borderlessButton).frame(width: 20)
                    .accessibilityLabel("More install options").help("More install options")
            }.disabled(updates.installing != nil || model.isBusy)
        } else {
            Button([RuntimeKind.mysql, .postgresql, .redis].contains(release.kind) ? "Install version" : "Update") {
                updates.install(release, model: model)
            }.disabled(updates.installing != nil || model.isBusy)
        }
    }
}
