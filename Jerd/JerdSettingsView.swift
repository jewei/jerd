import SwiftUI
import JerdCore

struct JerdSettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $model.selectedSettings) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section).padding(.vertical, 5)
            }.listStyle(.sidebar).frame(width: 170)
            Divider()
            Group {
                switch model.selectedSettings {
                case .general: GeneralSettingsView(appearance: model.appearance)
                case .runtimes: RuntimeSettingsView(model: model)
                case .advanced: AdvancedSettingsView(model: model)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: 860, height: 640)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var appearance: AppAppearance
    var body: some View {
        Form {
            Section("App visibility") {
                Toggle("Show in menu bar", isOn: $appearance.showMenuBar)
                Toggle("Show in Dock", isOn: $appearance.showDock)
                Text("When both are off, open Jerd from Applications to return to its window.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("App icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
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
                        }.buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                            .accessibilityValue(appearance.icon == choice ? "Selected" : "Not selected")
                    }
                }.padding(.vertical, 8)
                Text("The selected icon appears in the Dock and menu bar while Jerd is open.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

private struct AdvancedSettingsView: View {
    let model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Advanced").font(.largeTitle.bold())
                Text(model.runtimeMessage).foregroundStyle(.secondary)
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
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
            }.padding(24)
        }.disabled(model.isBusy)
    }
}
