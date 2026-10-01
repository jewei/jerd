import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var quitting = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        Task {
            await model?.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
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
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 540)
                .task { delegate.model = model; model.load() }
        }
        .defaultSize(width: 980, height: 660)
        MenuBarExtra("Jerd", systemImage: "server.rack") {
            MenuContent(model: model)
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
        Divider()
        Button("Quit Jerd") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
