import AppKit
import JerdDesign
import JerdUI
import Testing

@testable import JerdLive

/// The native split of the main window, and the toolbar rule: the section
/// picker and the sidebar button keep their place in every section and with a hidden sidebar.
@Suite("Workspace split", .serialized)
@MainActor
struct WorkspaceSplitTests {
    struct Positions: Equatable, CustomStringConvertible {
        let picker: NSRect
        let button: NSRect
        var description: String { "picker \(picker.minX)…\(picker.maxX), button \(button.minX)" }
    }

    /// Every section, then Sites with its sidebar hidden, then shown again.
    private static let navigation: [(AppState) -> Void] =
        AppSection.allCases.map { section in { $0.navigation.show(.section(section)) } } + [
            { $0.navigation.show(.section(.sites)) },
            { $0.navigation.toggleSidebar() },
            { $0.navigation.toggleSidebar() },
        ]

    @Test(
        "The picker and the sidebar button stay in place in every section and with a hidden sidebar",
        arguments: [WindowMetrics.standardSize.width, WindowMetrics.minimumSize.width])
    func toolbarItemsStayInPlace(width: CGFloat) throws {
        let window = try WorkspaceWindow(width: width)
        defer { window.close() }
        var found: [Positions] = []
        for change in Self.navigation {
            change(window.state)
            window.settle()
            found.append(
                Positions(picker: window.frame(of: window.picker), button: window.frame(of: window.sidebarButton)))
        }
        let first = try #require(found.first)
        #expect(first.picker.width > 0 && first.button.width > 0, "Toolbar items not found")
        #expect(first.button.maxX < first.picker.minX)
        #expect(abs(first.picker.midX - width / 2) <= 4, "The picker is not centered in the window: \(first)")
        for (index, positions) in found.enumerated() {
            #expect(positions == first, "Step \(index) moves an item: \(positions) instead of \(first)")
        }
    }

    @Test(
        "The sidebar edge never reaches under the section picker, also at the widest sidebar",
        arguments: [WindowMetrics.standardSize.width, WindowMetrics.minimumSize.width])
    func sidebarStaysLeftOfThePicker(width: CGFloat) throws {
        let window = try WorkspaceWindow(width: width)
        defer { window.close() }
        let split = try #require(window.split)
        split.splitView.setPosition(WindowMetrics.sidebarMaximumWidth + 40, ofDividerAt: 0)
        window.settle()
        let sidebar = window.frame(of: split.sidebarItem.viewController.view)
        #expect(sidebar.width >= SidebarWidthLimit.narrowestWidth)
        #expect(sidebar.maxX <= window.frame(of: window.picker).minX, "Sidebar \(sidebar.maxX)")
    }

    @Test("The sidebar is a lone .sidebar item in a plain split item, so AppKit draws the system background")
    func sidebarHasTheSystemSidebarItem() throws {
        let window = try WorkspaceWindow(width: WindowMetrics.standardSize.width)
        defer { window.close() }
        let split = try #require(window.split)
        // A plain outer item: a .sidebar item with a sibling moves the toolbar items.
        #expect(split.sidebarItem.behavior == .default)
        let sidebar = try #require(split.sidebarItem.viewController as? WorkspaceSidebarController)
        // One .sidebar item without a sibling: the system background without the toolbar layout.
        #expect(sidebar.splitViewItems.count == 1)
        #expect(sidebar.backgroundItem.behavior == .sidebar)
        #expect(!sidebar.backgroundItem.canCollapse)
        #expect(sidebar.backgroundItem.allowsFullHeightLayout)
    }

    @Test("The system sidebar background fills the column from the top edge of the window to the bottom")
    func sidebarBackgroundIsFullHeight() throws {
        let window = try WorkspaceWindow(width: WindowMetrics.standardSize.width)
        defer { window.close() }
        let split = try #require(window.split)
        let sidebar = try #require(split.sidebarItem.viewController as? WorkspaceSidebarController)
        let column = sidebar.backgroundItem.viewController.view
        let background = try #require(Self.systemBackground(above: column), "No system sidebar background")
        let content = try #require(window.window.contentView)
        for view in [background, column] {
            #expect(window.frame(of: view).minY == 0)
            #expect(window.frame(of: view).maxY == content.bounds.maxY)
            #expect(window.frame(of: view).width == window.frame(of: split.sidebarItem.viewController.view).width)
        }
        // The rows start below the toolbar.
        let rows = try #require(column.subviews.first)
        #expect(window.frame(of: rows).maxY <= window.window.contentLayoutRect.maxY)
    }

    @Test("Nothing of Jerd draws over the system sidebar background: no own material and no opaque layer")
    func nothingCoversTheSidebarBackground() throws {
        let window = try WorkspaceWindow(width: WindowMetrics.standardSize.width)
        defer { window.close() }
        let split = try #require(window.split)
        let sidebar = try #require(split.sidebarItem.viewController as? WorkspaceSidebarController)
        let column = sidebar.backgroundItem.viewController.view
        let hosting = try #require(column.subviews.first)
        // A window with a .sidebar item draws a title bar band over the whole width, also over
        // the sidebar top, unless the title bar is transparent.
        #expect(window.window.titlebarAppearsTransparent)
        // The views above the system background: AppKit's holder views, the column, and its host.
        let own = Self.ancestors(of: column).prefix { !Self.isSystemBackground($0) } + [column, hosting]
        for view in own {
            #expect(!view.isOpaque, "\(type(of: view)) is opaque")
            #expect(view.layer?.backgroundColor == nil, "\(type(of: view)) fills its layer")
            #expect(!(view is NSVisualEffectView), "\(type(of: view)) draws its own material")
        }
        // The hosted rows draw no material of their own either (the earlier sidebar drew one); only
        // the selected row has the system selection material.
        let materials = Self.descendants(of: hosting).compactMap { ($0 as? NSVisualEffectView)?.material }
        #expect(materials.allSatisfy { $0 == .selection }, "Materials: \(materials.map(\.rawValue))")
    }

    @Test("Hiding the sidebar collapses the split item, and a collapse in the split updates the navigation")
    func collapseFollowsNavigationBothWays() throws {
        let window = try WorkspaceWindow(width: WindowMetrics.standardSize.width)
        defer { window.close() }
        let split = try #require(window.split)
        window.state.navigation.show(.section(.sites))
        window.state.navigation.toggleSidebar()
        window.settle(passes: 30)
        #expect(split.sidebarItem.isCollapsed)

        split.sidebarItem.isCollapsed = false
        window.settle()
        #expect(window.state.navigation.isSidebarVisible(in: .sites))

        window.state.navigation.show(.section(.mail))
        window.settle()
        #expect(split.sidebarItem.isCollapsed)
        #expect(window.state.navigation.isSidebarVisible(in: .sites))
    }

    @Test("VoiceOver and Full Keyboard Access find a split group with a splitter")
    func splitterIsAccessible() throws {
        let window = try WorkspaceWindow(width: WindowMetrics.standardSize.width)
        defer { window.close() }
        let split = try #require(window.split)
        #expect(split.splitView.accessibilityRole() == .splitGroup)
        let roles = (split.splitView.accessibilityChildren() ?? []).compactMap { child in
            (child as? any NSAccessibilityProtocol)?.accessibilityRole()
        }
        #expect(roles.contains(.splitter), "Children: \(roles)")
    }

    @Test("The sidebar width is saved under the autosave name and comes back in a new window")
    func sidebarWidthIsSaved() throws {
        let name = "dev.jerd.live-tests.split.\(UUID().uuidString)"
        let key = "NSSplitView Subview Frames \(name)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let first = try WorkspaceWindow(width: WindowMetrics.standardSize.width, autosaveName: name)
        let split = try #require(first.split)
        split.splitView.setPosition(250, ofDividerAt: 0)
        first.settle()
        split.splitView.adjustSubviews()
        first.close()
        #expect(UserDefaults.standard.object(forKey: key) != nil)

        let second = try WorkspaceWindow(width: WindowMetrics.standardSize.width, autosaveName: name)
        defer { second.close() }
        let restored = try #require(second.split)
        #expect(abs(restored.sidebarItem.viewController.view.frame.width - 250) <= 1)
    }

    @Test("Only a sidebar change within one section animates; a section change does not")
    func onlyTheSidebarButtonAnimates() {
        #expect(WorkspaceSplitRepresentable.animatesSidebar(from: .sites, to: .sites))
        #expect(!WorkspaceSplitRepresentable.animatesSidebar(from: .sites, to: .mail))
        #expect(!WorkspaceSplitRepresentable.animatesSidebar(from: nil, to: .dashboard))
    }

    // MARK: View tree

    /// The view that AppKit draws the system sidebar background with: from macOS 26 a glass
    /// view, before it a visual effect view with the sidebar material.
    static func isSystemBackground(_ view: NSView) -> Bool {
        if #available(macOS 26, *), view is NSGlassEffectView { return true }
        return (view as? NSVisualEffectView)?.material == .sidebar
    }

    static func systemBackground(above view: NSView) -> NSView? {
        ancestors(of: view).first(where: isSystemBackground)
    }

    /// The superviews of `view`, nearest first.
    static func ancestors(of view: NSView) -> [NSView] {
        Array(sequence(first: view, next: \.superview).dropFirst())
    }

    static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
