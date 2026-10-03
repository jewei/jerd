// Run with capture-ui.py. Uses in-memory fixtures; never loads or starts services.
import AppKit
import SwiftUI
import JerdCore

@main
struct CaptureUI {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await capture() }
            catch { fputs("UI capture failed: \(error)\n", stderr); exit(1) }
            app.terminate(nil)
        }
        app.run()
    }

    @MainActor static func capture() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let filter = CommandLine.arguments.count > 2 ? Set(CommandLine.arguments[2].split(separator: ",").map(String.init)) : []
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = AppModel()
        model.isLoaded = true
        model.databases.isLoaded = true
        model.storage.isLoaded = true
        model.mail.isLoaded = true
        model.runtimeMessage = "PHP, Caddy, Composer, and the Laravel installer are installed and managed by Jerd."
        model.databases.runtimeMessage = "MySQL, PostgreSQL, and Redis are installed. Each service has its own data folder."
        model.mail.runtimeMessage = "Mailpit 1.31.3 is installed."
        model.storage.runtimeMessage = "RustFS 1.0.0 is installed."
        let php = DevelopmentRuntime(cliPath: "/preview/php", fpmPath: "/preview/php-fpm", version: "8.5.0", architectures: [.current], cliExtensions: [], fpmExtensions: [])
        model.configuration.runtimes = [php]
        model.configuration.defaultRuntimeID = php.id
        model.mail.configuration.runtime = MailRuntime(id: "preview", version: "1.31.3", path: "/preview/mailpit")
        model.storage.configuration.runtime = StorageRuntime(id: "preview", version: "1.0.0", path: "/preview/rustfs")
        let dbRuntime = DatabaseRuntime(id: "preview", engine: .postgresql, version: "17.5", path: "/preview/postgres")
        model.databases.configuration.runtimes = [dbRuntime]
        let site = Site(displayName: "Studio", projectPath: "/Users/developer/Projects/studio", documentRoot: "/Users/developer/Projects/studio/public", hostname: "studio.test")
        let database = DatabaseService(name: "Studio development", runtimeID: dbRuntime.id, port: 5432)
        let bucket = StorageBucket(name: "studio-assets", setupComplete: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Jerd · Visual review"
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let host = NSHostingView(rootView: JerdWorkspaceView(model: model).allowsHitTesting(false))
        window.contentView = host
        var captureCount = 0
        for dark in [false, true] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let theme = dark ? "dark" : "light"
            for compact in [false, true] {
                window.setContentSize(NSSize(width: compact ? 820 : 980, height: compact ? 540 : 660))
                let size = compact ? "compact" : "standard"
                let pages: [(String, AppSection, DashboardSection)] = [
                    ("dashboard", .dashboard, .dashboard), ("appearance", .dashboard, .appearance),
                    ("runtimes", .dashboard, .runtimes), ("advanced", .dashboard, .advanced), ("about", .dashboard, .about),
                    ("sites-empty", .sites, .dashboard), ("databases-empty", .databases, .dashboard),
                    ("storage-empty", .storage, .dashboard), ("mail", .mail, .dashboard),
                    ("sites", .sites, .dashboard), ("databases", .databases, .dashboard), ("storage", .storage, .dashboard),
                    ("dashboard-populated", .dashboard, .dashboard),
                    ("sites-long", .sites, .dashboard), ("databases-running", .databases, .dashboard),
                    ("storage-running", .storage, .dashboard), ("mail-running", .mail, .dashboard),
                    ("databases-error", .databases, .dashboard), ("storage-error", .storage, .dashboard),
                    ("mail-busy", .mail, .dashboard)]
                model.configuration.sites = []; model.selectedSiteID = nil
                model.databases.configuration.services = []; model.databases.selectedID = nil
                model.storage.configuration.buckets = []; model.storage.selectedName = nil
                model.databases.statuses = [:]
                model.storage.state = .stopped; model.storage.processID = nil
                model.mail.state = .stopped; model.mail.processID = nil; model.mail.isBusy = false
                for (name, section, dashboard) in pages {
                    if name == "sites" {
                        model.configuration.sites = [site]; model.selectedSiteID = site.id
                        model.databases.configuration.services = [database]; model.databases.selectedID = database.id
                        model.storage.configuration.buckets = [bucket]; model.storage.selectedName = bucket.name
                    }
                    switch name {
                    case "sites-long":
                        var longSite = site
                        longSite.displayName = "Studio customer portal and content management"
                        longSite.hostname = "studio-customer-portal.test"
                        model.configuration.sites = [longSite]
                    case "databases-running":
                        model.databases.statuses[database.id] = DatabaseStatus(state: .running, processID: 12345)
                    case "storage-running":
                        model.storage.state = .running; model.storage.processID = 12346
                        model.storage.availableBuckets = [bucket.name]
                    case "mail-running":
                        model.mail.state = .running; model.mail.processID = 12347
                    case "databases-error":
                        model.databases.statuses[database.id] = DatabaseStatus(state: .failed("The service could not start because port 5432 is already in use. Choose a different port and try again."))
                    case "storage-error":
                        model.storage.state = .failed("The storage service could not start. Check its log for details, then try again.")
                        model.storage.processID = nil
                    case "mail-busy":
                        model.mail.state = .starting; model.mail.processID = nil; model.mail.isBusy = true
                    default: break
                    }
                    model.selectedSection = section; model.selectedDashboard = dashboard
                    if !filter.isEmpty && !filter.contains(name) { continue }
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    try await Task.sleep(for: .milliseconds(750))
                    host.layoutSubtreeIfNeeded()
                    let destination = output.appendingPathComponent("\(name)-\(theme)-\(size).png")
                    try await captureWindow(window, to: destination)
                    captureCount += 1
                    if ["about", "appearance", "runtimes", "advanced", "sites", "databases", "storage", "mail"].contains(name),
                       let scroll = scrollViews(in: host).first(where: {
                           $0.frame.width > 350 && ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 40
                       }), let document = scroll.documentView {
                        let original = scroll.contentView.bounds.origin
                        let bottom = document.isFlipped ? max(0, document.frame.height - scroll.contentView.bounds.height) : 0
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        try await Task.sleep(for: .milliseconds(300))
                        try await captureWindow(window, to: output.appendingPathComponent("\(name)-\(theme)-\(size)-bottom.png"))
                        captureCount += 1
                        scroll.contentView.scroll(to: original)
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                }
            }
        }
        window.close()
        print("Captured \(captureCount) native views in \(output.path)")
    }

    @MainActor private static func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    @MainActor private static func captureWindow(_ window: NSWindow, to destination: URL) async throws {
        let windowID = String(window.windowNumber)
        try await Task.detached {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", windowID, destination.path]
            try capture.run()
            capture.waitUntilExit()
            guard capture.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        }.value
    }

}
