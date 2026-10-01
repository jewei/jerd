import SwiftUI
import JerdCore

struct DashboardView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your local environment").font(.largeTitle.bold())
                        Text("Sites and services on this Mac").font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    card("Sites", symbol: "globe", count: "\(model.configuration.sites.count) registered",
                         state: "\(model.runningSiteIDs.count) running", active: !model.runningSiteIDs.isEmpty, section: .sites) {
                        Button(model.runningSiteIDs.isEmpty ? "Start all sites" : "Stop all sites") {
                            if model.runningSiteIDs.isEmpty { model.start() } else { model.stop() }
                        }.disabled(model.isBusy || !model.configuration.sites.contains(where: \.isEnabled))
                    }
                    card("Databases", symbol: "externaldrive", count: "\(model.databases.configuration.services.count) services",
                         state: "\(model.databases.statuses.values.filter { $0.state == .running }.count) running",
                         active: model.databases.statuses.values.contains { $0.state == .running }, section: .databases) {
                        Text("MySQL · PostgreSQL · Redis").font(.callout).foregroundStyle(.secondary)
                    }
                    card("Storage", symbol: "externaldrive.badge.icloud", count: "\(model.storage.configuration.buckets.count) \(model.storage.configuration.buckets.count == 1 ? "bucket" : "buckets")",
                         state: model.storage.state.title, active: model.storage.state == .running, section: .storage) {
                        Button(model.storage.processID == nil ? "Start storage" : "Stop storage") {
                            if model.storage.processID == nil { model.storage.start() } else { model.storage.stop() }
                        }.disabled(!model.storage.canAdd)
                        Button("Open console") { model.storage.openConsole() }.disabled(model.storage.state != .running)
                    }
                    card("Mail", symbol: "envelope", count: "SMTP \(model.mail.configuration.smtpPort)",
                         state: model.mail.state.title, active: model.mail.state == .running, section: .mail) {
                        Button(model.mail.processID == nil ? "Start mail" : "Stop mail") {
                            if model.mail.processID == nil { model.mail.start() } else { model.mail.stop() }
                        }.disabled(!model.mail.canChange || model.mail.configuration.runtime == nil)
                        Button("Open inbox") { model.mail.openInbox() }.disabled(model.mail.state != .running)
                    }
                }
                GroupBox {
                    HStack(spacing: 14) {
                        Image(systemName: "shippingbox").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Managed runtimes").font(.headline)
                            Text("View installed versions and check for updates in Settings.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Manage runtimes") { model.selectedSettings = .runtimes; openSettings() }
                    }.padding(12)
                }
                ForEach(errors, id: \.self) { Text($0).foregroundStyle(.red).textSelection(.enabled) }
            }.padding(30)
        }
    }
    private var errors: [String] {
        [model.errorMessage, model.databases.errorMessage, model.storage.errorMessage, model.mail.errorMessage].compactMap { $0 }
    }
    private func card<Actions: View>(_ title: String, symbol: String, count: String, state: String,
                                    active: Bool, section: AppSection, @ViewBuilder actions: () -> Actions) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(title, systemImage: symbol).font(.title2.bold())
                    Spacer()
                    Label(state, systemImage: active ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(active ? Color.green : Color.secondary).font(.callout)
                }
                Text(count).foregroundStyle(.secondary)
                HStack { actions(); Spacer(); Button("View") { model.selectedSection = section }.accessibilityLabel("View \(title.lowercased())") }
            }.frame(maxWidth: .infinity, minHeight: 112, alignment: .leading).padding(16)
        }
    }
}
