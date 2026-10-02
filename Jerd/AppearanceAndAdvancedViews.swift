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
            }.frame(maxWidth: 1000, alignment: .leading).padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
        }.disabled(model.isBusy)
    }
}
