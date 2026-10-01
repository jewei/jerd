import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var quitting = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = JerdIcon.application { NSApp.applicationIconImage = icon }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        Task {
            let stopped = await model?.shutdown() ?? true
            if !stopped { quitting = false }
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
            TabView(selection: $model.selectedSection) {
                ContentView(model: model).tabItem { Label("Sites", systemImage: "globe") }.tag(AppSection.sites)
                DatabaseServicesView(model: model.databases)
                    .tabItem { Label("Databases", systemImage: "externaldrive") }.tag(AppSection.databases)
                StorageServicesView(model: model.storage)
                    .tabItem { Label("Storage", systemImage: "externaldrive.badge.icloud") }.tag(AppSection.storage)
                MailServiceView(model: model.mail)
                    .tabItem { Label("Mail", systemImage: "envelope") }.tag(AppSection.mail)
            }
                .frame(minWidth: 820, minHeight: 540)
                .task { delegate.model = model; model.load() }
        }
        .defaultSize(width: 980, height: 660)
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            if let icon = JerdIcon.menuBar {
                Image(nsImage: icon).renderingMode(.original).accessibilityLabel("Jerd")
            } else {
                Image(systemName: "server.rack").accessibilityLabel("Jerd")
            }
        }
    }
}

@MainActor
private enum JerdIcon {
    static let application = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }
    static let menuBar: NSImage? = {
        guard let icon = application?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 18, height: 18)
        icon.isTemplate = false
        return icon
    }()
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
        Divider()
        ForEach(model.configuration.sites.filter(\.isEnabled)) { site in
            Button("Open \(site.displayName)") { model.open(site) }.disabled(model.isBusy || !model.runningSiteIDs.contains(site.id))
        }
        if !model.runningSiteIDs.isEmpty {
            Button("Stop environment") { model.stop() }.disabled(model.isBusy)
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
        Button("Quit Jerd") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
