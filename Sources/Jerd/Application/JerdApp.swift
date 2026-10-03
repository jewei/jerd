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

/// The workspace has no startup effects, so previews can use in-memory models.
struct JerdWorkspaceView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedSection) {
                DashboardView(model: model)
                    .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }.tag(AppSection.dashboard)
                ContentView(model: model).tabItem { Label("Sites", systemImage: "globe") }.tag(AppSection.sites)
                DatabaseServicesView(model: model.databases)
                    .tabItem { Label("Databases", systemImage: "externaldrive") }.tag(AppSection.databases)
                StorageServicesView(model: model.storage)
                    .tabItem { Label("Storage", systemImage: "externaldrive.badge.icloud") }.tag(AppSection.storage)
                MailServiceView(model: model.mail)
                    .tabItem { Label("Mail", systemImage: "envelope") }.tag(AppSection.mail)
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
