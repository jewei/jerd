import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    var openMainWindow: (() -> Void)?
    private var quitting = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        model?.appearance.apply()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow?()
        sender.activate(ignoringOtherApps: true)
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        model?.appUpdates.isTerminating = true
        Task {
            let stopped = await model?.shutdown() ?? true
            if !stopped {
                quitting = false
                model?.appUpdates.isTerminating = false
            }
            sender.reply(toApplicationShouldTerminate: stopped)
        }
        return .terminateLater
    }
}

@main
struct JerdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    var body: some Scene {
        Window("Jerd", id: "main") {
            MainWindowView(model: model, delegate: delegate)
        }
        .defaultSize(width: 980, height: 660)
        .commands { JerdCommands(model: model) }
        MenuBarExtra(isInserted: Binding(get: { model.appearance.showMenuBar }, set: { model.appearance.showMenuBar = $0 })) {
            MenuContent(model: model)
        } label: {
            if let icon = model.appearance.menuImage {
                Image(nsImage: icon).renderingMode(.original).accessibilityLabel("Jerd")
            } else {
                Image(systemName: "server.rack").accessibilityLabel("Jerd")
            }
        }
    }
}

private struct JerdCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Jerd") { show(.about) }
            Button("Check for Updates…") { model.appUpdates.checkForUpdates() }
                .disabled(!model.appUpdates.canCheckForUpdates)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { show(.appearance) }.keyboardShortcut(",")
        }
    }

    private func show(_ section: DashboardSection) {
        model.showDashboard(section)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MainWindowView: View {
    @Bindable var model: AppModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        JerdWorkspaceView(model: model)
                .task {
                    delegate.model = model
                    delegate.openMainWindow = { openWindow(id: "main") }
                    model.appearance.apply()
                    model.load()
                    model.appUpdates.start()
                }
    }
}

enum WorkspaceSelection: Hashable {
    case dashboard(DashboardSection), site(UUID), tunnel(UUID), database(UUID), bucket(String)
}

/// The workspace has no startup effects, so previews can use in-memory models.
struct JerdWorkspaceView: View {
    @Bindable var model: AppModel
    @State var sites = SitePresentation()
    @State private var databases = DatabasePresentation()
    @State var storage = StoragePresentation()
    @State private var sidebarState = WorkspaceSidebarState()

    private var sitePage: ContentView { ContentView(presentation: sites, model: model) }
    private var databasePage: DatabaseServicesView { DatabaseServicesView(presentation: databases, model: model.databases) }
    private var storagePage: StorageServicesView { StorageServicesView(presentation: storage, model: model.storage) }

    var body: some View {
        WorkspacePages(model: model, sites: sites, databases: databases, storage: storage,
                       sidebarState: sidebarState, sidebar: AnyView(sidebar))
        .toolbar(removing: titleItem)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(sidebarAction, systemImage: "sidebar.left") {
                    sidebarState.toggle(model.selectedSection)
                }
                .help(model.selectedSection == .mail ? "Mail has no sidebar" : sidebarAction)
                .disabled(model.selectedSection == .mail)
            }
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $model.selectedSection) {
                    ForEach(AppSection.allCases, id: \.self) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItemGroup {
                switch model.selectedSection {
                case .sites: sitePage.toolbarActions
                case .databases: databasePage.toolbarActions
                case .storage: storagePage.toolbarActions
                default: EmptyView()
                }
            }
        }
        .transaction(value: model.selectedSection) { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .frame(minWidth: 820, minHeight: 540)
        .safeAreaInset(edge: .bottom) {
            if let message = model.operationMessage {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(message).font(.callout)
                    Spacer()
                    if model.isBusy && !model.isShuttingDown {
                        Button("Stop sites") { model.stop() }.disabled(!model.canStop)
                    }
                }.padding(12).background(.bar)
            }
        }
    }

    private var titleItem: ToolbarDefaultItemKind? {
        if #available(macOS 15, *) { .title } else { nil }
    }

    private var sidebarAction: String {
        sidebarState.isHidden(model.selectedSection) ? "Show sidebar" : "Hide sidebar"
    }

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            switch model.selectedSection {
            case .dashboard: DashboardView(model: model).sidebarRows
            case .sites: sitePage.sidebarRows
            case .databases: databasePage.sidebarRows
            case .storage: storagePage.sidebarRows
            case .mail: EmptyView()
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            switch model.selectedSection {
            case .sites: sitePage.sidebarFooter
            case .databases: databasePage.sidebarFooter
            case .storage: storagePage.sidebarFooter
            default: EmptyView()
            }
        }
    }

    private var sidebarSelection: Binding<WorkspaceSelection?> {
        Binding(get: {
            switch model.selectedSection {
            case .dashboard: .dashboard(model.selectedDashboard)
            case .sites:
                if let id = model.selectedTunnelID { .tunnel(id) }
                else { model.selectedSiteID.map(WorkspaceSelection.site) }
            case .databases: model.databases.selectedID.map(WorkspaceSelection.database)
            case .storage: model.storage.selectedName.map(WorkspaceSelection.bucket)
            case .mail: nil
            }
        }, set: { selection in
            // A native list refresh must not clear another section's selection.
            switch (model.selectedSection, selection) {
            case (.dashboard, .dashboard(let section)): model.selectedDashboard = section
            case (.sites, .site(let id)): model.selectedTunnelID = nil; model.selectedSiteID = id
            case (.sites, .tunnel(let id)): model.selectedSiteID = nil; model.selectedTunnelID = id
            case (.databases, .database(let id)): model.databases.selectedID = id
            case (.storage, .bucket(let name)): model.storage.selectedName = name
            default: break
            }
        })
    }
}

@MainActor @Observable
private final class WorkspaceSidebarState {
    var hidden: Set<AppSection> = []
    func isHidden(_ section: AppSection) -> Bool { section == .mail || hidden.contains(section) }
    func toggle(_ section: AppSection) {
        guard section != .mail else { return }
        if hidden.contains(section) { hidden.remove(section) } else { hidden.insert(section) }
    }
}

/// Resize the shared sidebar and select the retained detail in one native update.
private struct WorkspacePages: NSViewControllerRepresentable {
    let model: AppModel
    let sites: SitePresentation
    let databases: DatabasePresentation
    let storage: StoragePresentation
    let sidebarState: WorkspaceSidebarState
    let sidebar: AnyView

    func makeNSViewController(context: Context) -> WorkspaceController {
        let controller = WorkspaceController(sidebar: sidebar)
        let pages: [AnyView] = [
            AnyView(DashboardView(model: model)),
            AnyView(ContentView(presentation: sites, model: model)),
            AnyView(DatabaseServicesView(presentation: databases, model: model.databases)),
            AnyView(StorageServicesView(presentation: storage, model: model.storage)),
            AnyView(MailServiceView(model: model.mail))
        ]
        for (section, page) in zip(AppSection.allCases, pages) {
            controller.details.addPage(NSHostingController(rootView: page), section: section)
        }
        controller.details.onSelection = { [weak controller, weak model, weak sidebarState] index in
            guard let section = AppSection(rawValue: index), let model, let sidebarState else { return }
            controller?.setSidebarHidden(sidebarState.isHidden(section))
            if model.selectedSection != section { model.selectedSection = section }
        }
        controller.onSidebarCollapse = { [weak model, weak sidebarState] collapsed in
            guard let model, let sidebarState, model.selectedSection != .mail else { return }
            if collapsed { sidebarState.hidden.insert(model.selectedSection) }
            else { sidebarState.hidden.remove(model.selectedSection) }
        }
        controller.select(model.selectedSection, sidebarHidden: sidebarState.isHidden(model.selectedSection))
        return controller
    }

    func updateNSViewController(_ controller: WorkspaceController, context: Context) {
        controller.sidebar.rootView = sidebar
        controller.select(model.selectedSection, sidebarHidden: sidebarState.isHidden(model.selectedSection))
    }
}

private final class WorkspaceController: NSSplitViewController {
    let sidebar: NSHostingController<AnyView>
    let details = WorkspaceDetailController()
    var onSidebarCollapse: ((Bool) -> Void)?
    private var collapseObservation: NSKeyValueObservation?
    private var updatingSidebar = false

    init(sidebar: AnyView) {
        self.sidebar = NSHostingController(rootView: sidebar)
        super.init(nibName: nil, bundle: nil)
        let item = NSSplitViewItem(sidebarWithViewController: self.sidebar)
        item.minimumThickness = 200
        item.maximumThickness = 280
        item.preferredThicknessFraction = 220.0 / 980.0
        item.canCollapse = true
        item.canCollapseFromWindowResize = false
        item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        addSplitViewItem(item)
        addSplitViewItem(NSSplitViewItem(viewController: details))
        collapseObservation = item.observe(\.isCollapsed, options: [.new]) { [weak self] _, change in
            guard let collapsed = change.newValue else { return }
            // AppKit changes split-view geometry on the main thread.
            MainActor.assumeIsolated {
                guard let self, !self.updatingSidebar else { return }
                self.onSidebarCollapse?(collapsed)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSidebarHidden(_ hidden: Bool) {
        let wasUpdating = updatingSidebar
        updatingSidebar = true
        defer { updatingSidebar = wasUpdating }
        let item = splitViewItems[0]
        if item.isCollapsed != hidden { item.isCollapsed = hidden }
        view.layoutSubtreeIfNeeded()
    }

    func select(_ section: AppSection, sidebarHidden: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        setSidebarHidden(sidebarHidden)
        if details.selectedIndex != section.rawValue {
            details.selectedIndex = section.rawValue
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }
}

/// Keep every page attached to the window so navigation cannot dismiss a sheet.
final class WorkspaceDetailController: NSViewController {
    var onSelection: ((Int) -> Void)?
    private(set) var pages: [NSViewController] = []
    var selectedIndex = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            showSelectedPage()
            onSelection?(selectedIndex)
        }
    }

    override func loadView() {
        view = NSView()
        // Hide the page and its native controls in the same layer transaction.
        view.wantsLayer = true
    }

    func addPage(_ controller: NSViewController, section: AppSection) {
        precondition(section.rawValue == pages.count)
        addChild(controller)
        pages.append(controller)
        controller.view.wantsLayer = true
        controller.view.isHidden = section.rawValue != selectedIndex
        view.addSubview(controller.view)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSelectedPage()
    }

    private func showSelectedPage() {
        layoutSelectedPage()
        for (index, page) in pages.enumerated() {
            page.view.isHidden = index != selectedIndex
        }
    }

    private func layoutSelectedPage() {
        guard pages.indices.contains(selectedIndex) else { return }
        // The split view can extend behind the unified window toolbar.
        // Keep fixed page headers inside the unobscured content area.
        pages[selectedIndex].view.frame = view.safeAreaRect
    }

    @objc func selectNextTabViewItem(_ sender: Any?) {
        guard selectedIndex + 1 < pages.count else { return }
        selectedIndex += 1
    }

    @objc func selectPreviousTabViewItem(_ sender: Any?) {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
    }
}

private struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open Jerd") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Open databases") {
            model.selectedSection = .databases
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Open storage") {
            model.selectedSection = .storage
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Open mail") {
            model.selectedSection = .mail
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Text(model.stateLabel)
        if let message = model.operationMessage { Text(message) }
        Divider()
        ForEach(model.configuration.sites.filter(\.isEnabled)) { site in
            Button("Open \(site.displayName)") { model.open(site) }.disabled(model.isBusy || !model.runningSiteIDs.contains(site.id))
        }
        if !model.runningSiteIDs.isEmpty || model.isBusy {
            Button("Stop environment") { model.stop() }.disabled(!model.canStop)
        } else if model.configuration.sites.contains(where: \.isEnabled) {
            Button("Start all sites") { model.start() }.disabled(model.isBusy)
        }
        if !model.tunnels.configuration.tunnels.isEmpty {
            Menu("Tunnels") {
                ForEach(model.tunnels.configuration.tunnels) { tunnel in
                    Menu(tunnel.name) {
                        Text(model.tunnels.state(tunnel).title)
                        Button("Open public address") { model.tunnels.open(tunnel) }
                        Button("Manage tunnel…") {
                            model.showTunnel(tunnel.id)
                            openWindow(id: "main")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        if model.tunnels.isActive(tunnel) {
                            Button("Stop connector") { model.tunnels.stop(tunnel) }
                                .disabled(!model.tunnels.canStop(tunnel))
                        }
                    }
                }
            }
        }
        if !model.databases.configuration.services.isEmpty {
            Menu("Databases") {
                ForEach(model.databases.configuration.services) { service in
                    let active = model.databases.status(service).processID != nil
                    Button("\(active ? "Stop" : "Start") \(service.name)") {
                        if active { model.databases.stop(service) } else { model.databases.start(service) }
                    }.disabled(model.databases.isBusy(service))
                }
            }
        }
        Menu("Storage") {
            Button("Open console") { model.storage.openConsole() }.disabled(model.storage.state != .running)
            if model.storage.processID != nil {
                Button("Stop storage") { model.storage.stop() }.disabled(!model.storage.canChange)
            } else {
                Button("Start storage") { model.storage.start() }.disabled(!model.storage.canAdd)
            }
        }
        Menu("Mail") {
            Button("Open inbox") { model.mail.openInbox() }.disabled(model.mail.state != .running)
            if model.mail.processID != nil {
                Button("Stop mail") { model.mail.stop() }.disabled(!model.mail.canChange)
            } else {
                Button("Start mail") { model.mail.start() }
                    .disabled(!model.mail.canChange || model.mail.configuration.runtime == nil)
            }
        }
        Divider()
        Button("Settings…") {
            model.showDashboard(.appearance)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut(",")
        Button("About Jerd") {
            model.showDashboard(.about)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Check for Updates…") { model.appUpdates.checkForUpdates() }
            .disabled(!model.appUpdates.canCheckForUpdates)
        Button("Quit Jerd") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
