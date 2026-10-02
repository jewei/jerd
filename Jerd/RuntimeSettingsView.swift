import SwiftUI
import JerdCore

struct RuntimeSettingsView: View {
    let model: AppModel
    private var updates: RuntimeUpdatesModel { model.updates }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Runtimes").font(.largeTitle.bold())
                    Spacer()
                    if updates.isChecking { ProgressView().controlSize(.small) }
                    Button("Check for runtime updates") { updates.check(model: model) }
                        .disabled(updates.isChecking || updates.isShuttingDown)
                }
                Text("Choose a version, then install it. PHP versions remain available for sites that use them.")
                    .foregroundStyle(.secondary)
                if let error = updates.loadError { Text(error).foregroundStyle(.red) }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                ForEach(RuntimeKind.allCases) { kind in runtimeCard(kind) }
                Text("MySQL uses the 8.4 LTS series. PostgreSQL uses the 18 series from Postgres.app. Redis builds need the Xcode command line tools.")
                    .font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: 1000, alignment: .leading).padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func runtimeCard(_ kind: RuntimeKind) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(kind.title).font(.title3.bold())
                    Spacer()
                    let versions = updates.installedVersions(kind, model: model)
                    Text(versions.isEmpty ? "Unavailable" : versions.joined(separator: ", "))
                        .foregroundStyle(.secondary).textSelection(.enabled).id(versions)
                }
                if kind == .php { phpSelections }
                if let check = updates.checks[kind] {
                    if let error = check.error { Text(error).font(.callout).foregroundStyle(.red) }
                    if !check.releases.isEmpty {
                        HStack {
                            Picker("Available", selection: Binding(get: { updates.selections[kind] ?? "" }, set: { updates.selections[kind] = $0 })) {
                                ForEach(check.releases) { release in
                                    Text(release.versionLabel + (updates.isInstalled(release, model: model) ? " · Installed" : "")).tag(release.id)
                                }
                            }.labelsHidden().accessibilityLabel("\(kind.title) version").frame(maxWidth: 280)
                            Spacer()
                            if let release = updates.selectedRelease(kind) { installControl(release) }
                        }
                        if let release = updates.selectedRelease(kind) { Link("Release source", destination: release.source).font(.caption) }
                    }
                    Text("Checked \(check.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text("Updates have not been checked.").font(.callout).foregroundStyle(.secondary) }
                if updates.installing == kind, let progress = updates.progress {
                    HStack {
                        if let fraction = progress.fraction { ProgressView(value: fraction).frame(width: 120) }
                        else { ProgressView().controlSize(.small) }
                        Text(progress.message).font(.callout)
                        Spacer()
                        if updates.canCancel { Button("Cancel") { updates.cancelInstall() } }
                    }
                }
                if let message = updates.messages[kind] { Text(message).font(.callout).foregroundStyle(.secondary) }
                if let error = updates.errors[kind] { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                if kind == .mailpit || kind == .rustfs {
                    Text("An update restarts this service. Jerd keeps a local data backup for recovery.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var phpSelections: some View {
        VStack(spacing: 8) {
            ForEach(model.configuration.runtimes) { runtime in
                HStack {
                    Text("PHP \(runtime.version)").font(.callout)
                    Spacer()
                    if model.configuration.defaultRuntimeID == runtime.id { Text("Default").font(.callout).foregroundStyle(.secondary) }
                    else { Button("Use as default") { model.setDefaultRuntime(runtime.id) }.disabled(model.isBusy || updates.installing != nil) }
                }
            }
        }
    }
    @ViewBuilder private func installControl(_ release: RuntimeRelease) -> some View {
        if updates.isInstalled(release, model: model) {
            Label("Installed", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
        } else if release.kind == .php {
            HStack {
                Button("Install & use") { updates.install(release, model: model) }
                Menu {
                    Button("Install only") { updates.install(release, model: model, useAsDefault: false) }
                } label: { Image(systemName: "chevron.down") }.menuStyle(.borderlessButton).frame(width: 20)
            }.disabled(updates.installing != nil || model.isBusy)
        } else {
            Button([RuntimeKind.mysql, .postgresql, .redis].contains(release.kind) ? "Install version" : "Update") {
                updates.install(release, model: model)
            }.disabled(updates.installing != nil || model.isBusy)
        }
    }
}
