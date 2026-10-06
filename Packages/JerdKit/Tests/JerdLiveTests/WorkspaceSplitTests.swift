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

    @Test("The sidebar has the system sidebar material from the top edge of the window to the bottom")
    func sidebarIsFullHeightWithTheSidebarMaterial() throws {
        let window = try WorkspaceWindow(width: WindowMetrics.standardSize.width)
        defer { window.close() }
        let split = try #require(window.split)
        let sidebar = try #require(split.sidebarItem.viewController.view as? NSVisualEffectView)
        let content = try #require(window.window.contentView)
        #expect(sidebar.material == .sidebar)
        #expect(window.frame(of: sidebar).minY == 0)
        #expect(window.frame(of: sidebar).maxY == content.bounds.maxY)
        // The rows start below the toolbar.
        let rows = try #require(sidebar.subviews.first)
        #expect(window.frame(of: rows).maxY <= window.window.contentLayoutRect.maxY)
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

    @Test("The sidebar limit keeps a gap to the picker and narrows the sidebar only in a narrow window")
    func sidebarWidthLimit() {
        #expect(SidebarWidthLimit.widths(windowWidth: 980, pickerWidth: 360) == 200...280)
        #expect(SidebarWidthLimit.widths(windowWidth: 980, pickerWidth: 440) == 200...262)
        #expect(SidebarWidthLimit.widths(windowWidth: 820, pickerWidth: 440) == 182...182)
        #expect(SidebarWidthLimit.widths(windowWidth: 600, pickerWidth: 440) == 160...160)
    }

    @Test("Only a sidebar change within one section animates; a section change does not")
    func onlyTheSidebarButtonAnimates() {
        #expect(WorkspaceSplitRepresentable.animatesSidebar(from: .sites, to: .sites))
        #expect(!WorkspaceSplitRepresentable.animatesSidebar(from: .sites, to: .mail))
        #expect(!WorkspaceSplitRepresentable.animatesSidebar(from: nil, to: .dashboard))
    }
}
