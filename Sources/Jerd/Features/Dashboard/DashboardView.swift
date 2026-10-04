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

    var sidebarRows: some View {
        ForEach(DashboardSection.allCases) { section in
            Label {
                Text(section.rawValue).fontWeight(.medium)
            } icon: {
                Image(systemName: section.symbol)
                    .symbolVariant(model.selectedDashboard == section ? .fill : .none)
            }
            .padding(.vertical, 7).tag(WorkspaceSelection.dashboard(section))
        }
    }

    var body: some View {
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

private struct DashboardOverview: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader("Dashboard", subtitle: "Your local development environment")
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(errors, id: \.self) { InlineMessage($0) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 16)], spacing: 16) {
                        sitesCard
                        databasesCard
                        storageCard
                        mailCard
                    }
                    runtimesCard
                }
                .padding(.horizontal, 30).padding(.vertical, 24)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var errors: [String] {
        [model.errorMessage, model.databases.errorMessage, model.storage.errorMessage, model.mail.errorMessage, model.tunnels.errorMessage].compactMap { $0 }
    }

    private var sitesCard: some View {
        let sites = model.configuration.sites
        let running = model.runningSiteIDs.count
        let enabled = sites.filter(\.isEnabled).count
        let status: (String, StatusTone) = model.isBusy ? (model.stateLabel, .busy)
            : running > 0 ? ("\(running) running", .ready)
            : sites.isEmpty ? ("No sites", .idle) : (model.stateLabel, model.environmentState.tone)
        return card("Sites", symbol: "globe", status: status,
                    summary: sites.isEmpty ? "Register an existing PHP project to serve it over HTTPS." :
                        "\(sites.count) registered · \(enabled) enabled" + tunnelSummary, section: .sites) {
            if !sites.isEmpty || model.isBusy {
                let stopping = model.isBusy || !model.runningSiteIDs.isEmpty
                Button(stopping ? "Stop all sites" : "Start all sites") {
                    if stopping { model.stop() } else { model.start() }
                }.disabled(stopping ? !model.canStop : enabled == 0)
            }
        }
    }

    private var tunnelSummary: String {
        let count = model.tunnels.configuration.tunnels.count
        guard count > 0 else { return "" }
        let connected = model.tunnels.states.values.filter { $0.state == .connected }.count
        return " · \(connected)/\(count) tunnels connected"
    }

    private var databasesCard: some View {
        let services = model.databases.configuration.services
        let states = services.map { model.databases.status($0).state }
        let running = states.filter { $0 == .running }.count
        let status: (String, StatusTone) = states.contains(where: { if case .failed = $0 { true } else { false } }) ? ("Failed", .failed)
            : states.contains(where: \.isBusy) ? ("Working…", .busy)
            : running > 0 ? ("\(running) of \(services.count) running", .ready)
            : services.isEmpty ? ("No services", .idle) : ("Stopped", .idle)
        return card("Databases", symbol: "externaldrive", status: status,
                    summary: services.isEmpty ? "Add MySQL, PostgreSQL, or Redis services." :
                        services.map(\.name).joined(separator: ", "), section: .databases) { EmptyView() }
    }

    private var storageCard: some View {
        let storage = model.storage
        let count = storage.configuration.buckets.count
        return card("Storage", symbol: "externaldrive.badge.icloud",
                    status: (storage.state.title, storage.isBusy ? .busy : storage.state.tone),
                    summary: "\(count) \(count == 1 ? "bucket" : "buckets") · S3 port \(String(storage.configuration.apiPort))",
                    section: .storage) {
            Button(storage.processID == nil ? "Start storage" : "Stop storage") {
                if storage.processID == nil { storage.start() } else { storage.stop() }
            }.disabled(storage.processID == nil ? !storage.canAdd : !storage.canChange)
            Button("Open console") { storage.openConsole() }.disabled(storage.state != .running)
        }
    }

    private var mailCard: some View {
        let mail = model.mail
        return card("Mail", symbol: "envelope",
                    status: (mail.state.title, mail.isBusy ? .busy : mail.state.tone),
                    summary: "SMTP port \(String(mail.configuration.smtpPort)) · Web port \(String(mail.configuration.webPort))",
                    section: .mail) {
            Button(mail.processID == nil ? "Start mail" : "Stop mail") {
                if mail.processID == nil { mail.start() } else { mail.stop() }
            }.disabled(!mail.canChange || (mail.processID == nil && mail.configuration.runtime == nil))
            Button("Open inbox") { mail.openInbox() }.disabled(mail.state != .running)
        }
    }

    private var runtimesCard: some View {
        let php = model.configuration.runtimes.first { $0.id == model.configuration.defaultRuntimeID }
        return HStack(alignment: .center, spacing: 16) {
                ServiceIcon(symbol: "shippingbox", tint: .secondary, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Runtimes").font(.headline)
                    Text(php.map { "PHP \($0.version) is the default. View installed versions and check for updates." } ??
                            "View installed versions and check for updates.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button { model.showDashboard(.runtimes) } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Manage runtimes").help("Manage runtimes")
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.35)))
    }

    private func card<Actions: View>(_ title: String, symbol: String, status: (String, StatusTone), summary: String,
                                     section: AppSection, @ViewBuilder actions: () -> Actions) -> some View {
        let view = Button { model.selectedSection = section } label: {
            Label("Open", systemImage: "arrow.right")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Open \(title.lowercased())")
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    ServiceIcon(symbol: symbol, size: 46)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        StatusBadge(title: status.0, tone: status.1)
                    }
                    Spacer(minLength: 0)
                }
                Text(summary).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true).help(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            Divider().opacity(0.55)
            Group {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { actions(); Spacer(minLength: 0); view }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) { actions(); Spacer(minLength: 0) }
                        view
                    }
                }
            }
            .controlSize(.regular)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 52)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.45)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
