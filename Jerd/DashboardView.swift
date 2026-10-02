import SwiftUI
import JerdCore

enum DashboardSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard", appearance = "Appearance", runtimes = "Runtimes"
    case advanced = "Advanced", about = "About"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .appearance: "paintbrush"
        case .runtimes: "shippingbox"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

struct DashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $model.selectedDashboard) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .padding(.vertical, 5).tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Dashboard")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            Group {
                switch model.selectedDashboard {
                case .dashboard: DashboardOverview(model: model)
                case .appearance: AppearanceView(appearance: model.appearance)
                case .runtimes: RuntimeSettingsView(model: model)
                case .advanced: AdvancedSettingsView(model: model)
                case .about: AboutView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DashboardOverview: View {
    let model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dashboard").font(.largeTitle.bold())
                    Text("Sites and services on this Mac").font(.title3).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
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
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Image(systemName: "shippingbox").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Managed runtimes").font(.headline)
                                Text("View installed versions and check for runtime updates.").foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Button("Manage runtimes") { model.showDashboard(.runtimes) }
                    }.padding(12)
                }
                ForEach(errors, id: \.self) { Text($0).foregroundStyle(.red).textSelection(.enabled) }
            }.frame(maxWidth: 1100, alignment: .leading).padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    private var errors: [String] {
        [model.errorMessage, model.databases.errorMessage, model.storage.errorMessage, model.mail.errorMessage].compactMap { $0 }
    }
    private func card<Actions: View>(_ title: String, symbol: String, count: String, state: String,
                                    active: Bool, section: AppSection, @ViewBuilder actions: () -> Actions) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: symbol).font(.title2.bold())
                    Label(state, systemImage: active ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(active ? Color.green : Color.secondary).font(.callout)
                }
                Text(count).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        actions()
                        Spacer()
                        Button("View") { model.selectedSection = section }.accessibilityLabel("View \(title.lowercased())")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { actions(); Spacer(minLength: 0) }
                        Button("View") { model.selectedSection = section }.accessibilityLabel("View \(title.lowercased())")
                    }
                }
            }.frame(maxWidth: .infinity, minHeight: 112, alignment: .leading).padding(16)
        }
    }
}
