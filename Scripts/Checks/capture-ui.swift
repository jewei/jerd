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
        model.tunnels.isLoaded = true
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
        let tunnel = TunnelRegistration(name: "Studio public preview", hostname: "preview.example.com", siteID: site.id, metricsPort: 20400)
        model.tunnels.configuration.runtime = TunnelRuntime(id: "preview", version: "2026.9.3", path: "/preview")
        let bucket = StorageBucket(name: "studio-assets", setupComplete: true)
        if filter.contains("navigation") || filter.contains("navigation-compact") {
            model.configuration.sites = [site]; model.selectedSiteID = site.id
            model.databases.configuration.services = [database]; model.databases.selectedID = database.id
            model.storage.configuration.buckets = [bucket]; model.storage.selectedName = bucket.name
            try await captureNavigation(model: model, output: output, compact: filter.contains("navigation-compact"))
            return
        }
        var captureCount = 0
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            for compact in [false, true] {
                // Use a fresh native window so toolbar backgrounds do not retain
                // stale frames from a prior appearance or size fixture.
                model.selectedSection = .dashboard
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: compact ? 820 : 980, height: compact ? 540 : 660),
                                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.title = "Jerd · Visual review"
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.center()
                let host = NSHostingView(rootView: JerdWorkspaceView(model: model).allowsHitTesting(false))
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                let size = compact ? "compact" : "standard"
                let pages: [(String, AppSection, DashboardSection)] = [
                    ("dashboard", .dashboard, .dashboard), ("appearance", .dashboard, .appearance),
                    ("runtimes", .dashboard, .runtimes), ("advanced", .dashboard, .advanced), ("about", .dashboard, .about),
                    ("sites-empty", .sites, .dashboard), ("databases-empty", .databases, .dashboard),
                    ("storage-empty", .storage, .dashboard), ("mail", .mail, .dashboard),
                    ("sites", .sites, .dashboard), ("databases", .databases, .dashboard), ("storage", .storage, .dashboard),
                    ("dashboard-populated", .dashboard, .dashboard),
                    ("sites-long", .sites, .dashboard), ("sites-running", .sites, .dashboard),
                    ("sites-stopped", .sites, .dashboard), ("databases-running", .databases, .dashboard),
                    ("storage-running", .storage, .dashboard), ("mail-running", .mail, .dashboard),
                    ("databases-error", .databases, .dashboard), ("storage-error", .storage, .dashboard),
                    ("mail-busy", .mail, .dashboard), ("tunnel-stopped", .sites, .dashboard),
                    ("tunnel-connected", .sites, .dashboard), ("tunnel-error", .sites, .dashboard)]
                model.tunnels.configuration.tunnels = []; model.selectedTunnelID = nil
                model.tunnels.states = [:]
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
                    model.environmentState = .stopped
                    model.runningSiteIDs = []
                    switch name {
                    case "sites-running", "sites-stopped":
                        let second = Site(displayName: "API", projectPath: "/preview/api", documentRoot: "/preview/api/public", hostname: "api.test")
                        model.configuration.sites = [site, second]
                        model.selectedSiteID = name == "sites-running" ? site.id : second.id
                        model.runningSiteIDs = [site.id]
                        model.environmentState = .running
                    case "tunnel-stopped", "tunnel-connected", "tunnel-error":
                        model.configuration.sites = [site]
                        model.tunnels.configuration.tunnels = [tunnel]
                        model.showTunnel(tunnel.id)
                        let state: TunnelState = name == "tunnel-connected" ? .connected : name == "tunnel-error" ? .failed("The connector could not authenticate. Replace its token and try again.") : .stopped
                        model.tunnels.states[tunnel.id] = TunnelSnapshot(registration: tunnel, state: state, processID: name == "tunnel-connected" ? 12348 : nil)
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
                    if ["about", "appearance", "runtimes", "advanced", "sites", "databases", "storage", "mail", "tunnel-stopped", "tunnel-connected", "tunnel-error"].contains(name),
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
                window.close()
            }
        }
        print("Captured \(captureCount) native views in \(output.path)")
    }

    @MainActor private static func captureNavigation(model: AppModel, output: URL, compact: Bool) async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: compact ? 820 : 980, height: compact ? 540 : 660),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Jerd · Navigation review"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        let sites = SitePresentation()
        let storage = StoragePresentation()
        window.contentView = NSHostingView(rootView: JerdWorkspaceView(model: model, sites: sites, storage: storage))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .seconds(1))
        guard let root = window.contentView?.superview,
              let picker = descendants(root).compactMap({ $0 as? NSSegmentedControl }).first(where: { $0.segmentCount == 5 }),
              let split = descendants(root).compactMap({ $0 as? NSSplitView }).first,
              let splitController = split.delegate as? NSSplitViewController,
              let tabs = splitController.children.compactMap({ $0 as? WorkspaceDetailController }).first else {
            throw JerdError.invalid("The navigation controls are missing.")
        }
        let pickerFrame = picker.convert(picker.bounds, to: nil)
        let firstDetail = tabs.pages[0]
        func checkSelection(_ section: AppSection) throws {
            guard model.selectedSection == section, tabs.selectedIndex == section.rawValue else {
                throw JerdError.invalid("The section control, sidebar, and detail are out of sync.")
            }
            let frame = picker.convert(picker.bounds, to: nil)
            guard abs(frame.minX - pickerFrame.minX) < 1, abs(frame.width - pickerFrame.width) < 1 else {
                throw JerdError.invalid("The section control moved during navigation: \(pickerFrame) → \(frame).")
            }
        }
        func select(_ section: AppSection, delay: Duration = .milliseconds(700)) async throws {
            let point = picker.convert(NSPoint(x: picker.bounds.width * (CGFloat(section.rawValue) + 0.5) / 5,
                                                y: picker.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else {
                    throw JerdError.invalid("Cannot create a navigation click.")
                }
                NSApp.postEvent(event, atStart: false)
            }
            try await Task.sleep(for: delay)
            try checkSelection(section)
        }
        let windowID = String(window.windowNumber)
        let movie = output.appendingPathComponent("navigation-\(UUID().uuidString).mov")
        let recording = Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-v", "-V", "18", "-l", windowID, movie.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        try await Task.sleep(for: .seconds(2))
        for section in [AppSection.sites, .databases, .storage, .mail, .dashboard, .sites, .dashboard] {
            try await select(section)
        }
        for section in [DashboardSection.appearance, .runtimes, .advanced, .about, .dashboard] {
            model.selectedDashboard = section
            try await Task.sleep(for: .milliseconds(700))
        }
        for section in [AppSection.sites, .databases, .storage, .mail, .dashboard] {
            try await select(section, delay: .milliseconds(180))
        }
        try await recording.value
        print("Recorded clicks and stable toolbar: \(movie.path)"); fflush(stdout)
        guard tabs.pages[0] === firstDetail else {
            throw JerdError.invalid("The Dashboard detail controller was replaced.")
        }
        try await verifyNavigationState(model: model, sites: sites, storage: storage, window: window, tabs: tabs, split: split)
        window.close()
        print("Captured navigation transitions in \(movie.path)")
    }

    @MainActor private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    @MainActor private static func verifyNavigationState(model: AppModel, sites: SitePresentation,
        storage: StoragePresentation, window: NSWindow, tabs: WorkspaceDetailController, split: NSSplitView) async throws {
        // Native next/previous actions must also update the SwiftUI selection.
        tabs.selectNextTabViewItem(nil)
        try await Task.sleep(for: .milliseconds(200))
        guard model.selectedSection == .sites else { throw JerdError.invalid("Native next-tab selection was not synchronized.") }
        tabs.selectPreviousTabViewItem(nil)
        try await Task.sleep(for: .milliseconds(200))
        guard model.selectedSection == .dashboard else { throw JerdError.invalid("Native previous-tab selection was not synchronized.") }

        // A wider sidebar and a scrolled detail must survive a Mail round trip.
        split.setPosition(250, ofDividerAt: 0)
        model.selectedDashboard = .runtimes
        try await Task.sleep(for: .milliseconds(300))
        let width = split.arrangedSubviews[0].frame.width
        guard let detail = tabs.selectedIndex >= 0 ? tabs.pages[tabs.selectedIndex].view : nil,
              let scroll = scrollViews(in: detail).first(where: { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 80 }) else {
            throw JerdError.invalid("The Runtimes scroll fixture is missing.")
        }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        let origin = scroll.contentView.bounds.origin
        model.selectedSection = .mail
        try await Task.sleep(for: .milliseconds(300))
        model.selectedSection = .dashboard
        try await Task.sleep(for: .milliseconds(300))
        guard abs(split.arrangedSubviews[0].frame.width - width) < 1, scroll.contentView.bounds.origin == origin else {
            throw JerdError.invalid("Sidebar width or detail scroll position was lost.")
        }

        try clickToolbarItem("Hide sidebar", in: window)
        try await Task.sleep(for: .milliseconds(350))
        guard split.isSubviewCollapsed(split.arrangedSubviews[0]) else { throw JerdError.invalid("Hide sidebar did not collapse the sidebar.") }
        model.selectedSection = .sites
        try await Task.sleep(for: .milliseconds(300))
        guard !split.isSubviewCollapsed(split.arrangedSubviews[0]) else { throw JerdError.invalid("Sites inherited Dashboard's hidden sidebar.") }
        model.selectedSection = .dashboard
        try await Task.sleep(for: .milliseconds(300))
        guard split.isSubviewCollapsed(split.arrangedSubviews[0]) else { throw JerdError.invalid("Dashboard's sidebar visibility was lost.") }
        try clickToolbarItem("Show sidebar", in: window)
        try await Task.sleep(for: .milliseconds(350))
        guard let splitController = split.delegate as? NSSplitViewController else {
            throw JerdError.invalid("Missing native split controller.")
        }
        splitController.splitViewItems[0].isCollapsed = true
        try await Task.sleep(for: .milliseconds(300))
        try clickToolbarItem("Show sidebar", in: window)
        try await Task.sleep(for: .milliseconds(300))
        guard !splitController.splitViewItems[0].isCollapsed else {
            throw JerdError.invalid("Native collapse did not update the toolbar action.")
        }
        print("Native selection, sidebar, and scroll checks passed."); fflush(stdout)

        // Editors must remain attached and usable through menu-style navigation.
        model.selectedSection = .sites
        try await Task.sleep(for: .milliseconds(300))
        sites.editingSite = model.configuration.sites.first
        try await Task.sleep(for: .milliseconds(350))
        guard let sheet = window.attachedSheet else { throw JerdError.invalid("The site editor did not open.") }
        model.showDashboard(.appearance)
        try await Task.sleep(for: .milliseconds(300))
        guard window.attachedSheet === sheet else {
            throw JerdError.invalid("Navigation discarded or disabled the site editor.")
        }
        try pressEscape(in: sheet)
        try await Task.sleep(for: .milliseconds(350))
        guard window.attachedSheet == nil else { throw JerdError.invalid("The site editor did not close.") }
        model.selectedSection = .storage
        try await Task.sleep(for: .milliseconds(300))
        storage.settings = true
        try await Task.sleep(for: .milliseconds(350))
        guard let storageSheet = window.attachedSheet else { throw JerdError.invalid("Storage settings did not open.") }
        try pressEscape(in: storageSheet)
        try await Task.sleep(for: .milliseconds(350))
        guard window.attachedSheet == nil else { throw JerdError.invalid("Storage settings did not close.") }
        print("Navigation checks passed: clicks, native selection, stable toolbar, retained sidebar width, scroll, and editors.")
    }

    @MainActor private static func clickToolbarItem(_ title: String, in window: NSWindow) throws {
        guard let root = window.contentView?.superview,
              let item = descendants(root).first(where: {
                  [$0.accessibilityTitle(), $0.accessibilityLabel(), $0.accessibilityHelp()].contains(title)
              }) else { throw JerdError.invalid("Missing toolbar item: \(title)") }
        let point = item.convert(NSPoint(x: item.bounds.midX, y: item.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else {
                throw JerdError.invalid("Cannot create a toolbar click.")
            }
            NSApp.postEvent(event, atStart: false)
        }
    }

    @MainActor private static func pressEscape(in window: NSWindow) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53) else { throw JerdError.invalid("Cannot create an Escape key event.") }
            NSApp.postEvent(event, atStart: false)
        }
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
