import AppKit
import JerdDesign
import JerdUIFixtures
import SwiftUI
import Testing

@testable import JerdSnapshotSupport
@testable import JerdUI

@Suite("Workspace layout", .serialized)
@MainActor
struct WorkspaceLayoutTests {
    /// The smallest window that the workspace accepts, toolbar included, in a window like the
    /// app's: unified toolbar, full-size content view.
    private func minimumWindowSize(for state: AppState) -> CGSize {
        _ = NSApplication.shared
        let size = WindowMetrics.minimumSize
        let window = SnapshotWindow.make(size: size, chrome: .window(title: "Jerd"), appearance: nil)
        defer { window.close() }
        let host = NSHostingView(rootView: JerdWorkspace(state: state))
        host.sceneBridgingOptions = [.toolbars, .title]
        host.sizingOptions = [.minSize]
        window.contentView = host
        for _ in 0..<10 {
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        // With `.minSize`, the hosting view sets the window's content minimum: the content
        // minimum plus the toolbar inset.
        return window.contentMinSize
    }

    @Test("At the minimum window size the content fits below the toolbar, so nothing is cut off")
    func minimumWindowFits() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        fixture.state.navigation.show(.section(.databases))
        let minimum = minimumWindowSize(for: fixture.state)
        #expect(minimum.width <= WindowMetrics.minimumSize.width)
        #expect(minimum.height <= WindowMetrics.minimumSize.height)
        #expect(
            JerdWorkspace.minimumContentSize.height + JerdWorkspace.toolbarHeight == WindowMetrics.minimumSize.height)
    }
}
