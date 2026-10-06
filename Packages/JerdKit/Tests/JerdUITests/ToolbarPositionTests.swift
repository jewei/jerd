import AppKit
import JerdDesign
import JerdUIFixtures
import SwiftUI
import Testing

@testable import JerdSnapshotSupport
@testable import JerdUI

/// The section picker and the sidebar button keep their place during navigation,
/// also on Mail, which has no sidebar, and when the user hides a sidebar. This suite checks the
/// SwiftUI split of the snapshots (`WorkspaceStackSplit`); `WorkspaceSplitTests` in JerdLive
/// checks the native split of the app.
@Suite("Toolbar positions", .serialized)
@MainActor
struct ToolbarPositionTests {
    /// The window frames of the section picker and the sidebar button.
    struct Positions: Equatable, CustomStringConvertible {
        let picker: NSRect
        let toggle: NSRect
        var description: String { "picker \(picker.minX), button \(toggle.minX)" }
    }

    /// Shows each state in a window like the app's (unified toolbar) and reads the positions.
    private func positions(width: CGFloat, after changes: [(AppState) -> Void]) async -> [Positions] {
        _ = NSApplication.shared
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        let size = CGSize(width: width, height: WindowMetrics.standardSize.height)
        let window = SnapshotWindow.make(size: size, chrome: .window(title: "Jerd"), appearance: nil)
        defer { window.close() }
        let host = NSHostingView(rootView: JerdWorkspace(state: fixture.state))
        host.sceneBridgingOptions = [.toolbars, .title]
        window.contentView = host
        var result: [Positions] = []
        for change in changes {
            change(fixture.state)
            settle(window)
            result.append(positions(in: window))
        }
        return result
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<15 {
            window.layoutIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// The picker is the toolbar item with the segmented control; the sidebar button is the
    /// leading item of the others.
    private func positions(in window: NSWindow) -> Positions {
        let frames = (window.toolbar?.items ?? []).compactMap { item -> (NSRect, Bool)? in
            guard let view = item.view, !view.isHiddenOrHasHiddenAncestor else { return nil }
            return (view.convert(view.bounds, to: nil), contains(NSSegmentedControl.self, in: view))
        }
        let picker = frames.first { $0.1 }?.0 ?? .zero
        let toggle = frames.filter { !$0.1 }.map(\.0).min { $0.minX < $1.minX } ?? .zero
        return Positions(picker: picker, toggle: toggle)
    }

    private func contains(_ type: NSView.Type, in view: NSView) -> Bool {
        view.isKind(of: type) || view.subviews.contains { contains(type, in: $0) }
    }

    /// Every section, then Sites with its sidebar hidden by the user.
    private static let navigation: [(AppState) -> Void] =
        AppSection.allCases.map { section in { $0.navigation.show(.section(section)) } } + [
            { $0.navigation.show(.section(.sites)) },
            { $0.navigation.toggleSidebar() },
        ]

    @Test(
        "The picker and the sidebar button stay in place in every section and with a hidden sidebar",
        arguments: [WindowMetrics.standardSize.width, WindowMetrics.minimumSize.width])
    func toolbarItemsStayInPlace(width: CGFloat) async {
        let found = await positions(width: width, after: Self.navigation)
        let first = found[0]
        #expect(first.picker.width > 0 && first.toggle.width > 0, "Toolbar items not found")
        #expect(first.toggle.maxX < first.picker.minX)
        for (index, positions) in found.enumerated() {
            #expect(positions == first, "Step \(index) moves an item: \(positions) instead of \(first)")
        }
    }

    @Test(
        "The snapshot sidebar keeps the app's width limit, so its edge stays left of the picker",
        arguments: [WindowMetrics.standardSize.width, WindowMetrics.minimumSize.width])
    func snapshotSidebarStaysLeftOfThePicker(width: CGFloat) async throws {
        let picker = try #require(await positions(width: width, after: [{ _ in }]).first).picker
        let sidebar = WorkspaceStackSplit.sidebarWidth(windowWidth: width)
        #expect(picker.width > 0, "Picker not found")
        #expect(sidebar + SidebarWidthLimit.pickerGap <= picker.minX, "Sidebar \(sidebar), picker \(picker.minX)")
        #expect(sidebar == SidebarWidthLimit.idealWidth(windowWidth: width, pickerWidth: picker.width))
    }

}
