import AppKit
import JerdUI
import SwiftUI

/// The main window's split on the native AppKit split view (`WorkspaceSplitController`), for
/// `JerdWorkspace(state:split:)`. It reaches under the toolbar, so the sidebar is full height.
public struct WorkspaceSplit: View {
    /// The defaults name of the saved sidebar width. It is the name that the earlier
    /// `NavigationSplitView` window used, so an update keeps the user's width.
    public static let autosaveName = "main, SidebarNavigationSplitView"

    let columns: WorkspaceColumns
    let autosaveName: String?

    /// - Parameter autosaveName: The defaults name of the saved width; nil saves none.
    public init(columns: WorkspaceColumns, autosaveName: String? = Self.autosaveName) {
        self.columns = columns
        self.autosaveName = autosaveName
    }

    public var body: some View {
        WorkspaceSplitRepresentable(columns: columns, autosaveName: autosaveName)
            .ignoresSafeArea(.container, edges: .top)
    }
}

/// Builds the split controller once and applies each navigation change to it.
struct WorkspaceSplitRepresentable: NSViewControllerRepresentable {
    let columns: WorkspaceColumns
    let autosaveName: String?

    func makeNSViewController(context: Context) -> WorkspaceSplitController {
        let controller = WorkspaceSplitController(
            sidebar: NSHostingController(rootView: columns.sidebar),
            detail: NSHostingController(rootView: columns.detail),
            autosaveName: autosaveName)
        controller.show(sidebarVisible: columns.isSidebarVisible, animated: false)
        context.coordinator.section = columns.section
        let columns = columns
        controller.onSidebarCollapse = { isCollapsed in columns.recordSidebarVisible(!isCollapsed) }
        return controller
    }

    func updateNSViewController(_ controller: WorkspaceSplitController, context: Context) {
        let animated = Self.animatesSidebar(from: context.coordinator.section, to: columns.section)
        context.coordinator.section = columns.section
        controller.show(sidebarVisible: columns.isSidebarVisible, animated: animated)
    }

    /// The sidebar button and ⌃⌘S slide the sidebar, like every macOS sidebar. A section change
    /// shows the new section in one frame, also when its sidebar state differs.
    static func animatesSidebar(from previous: AppSection?, to section: AppSection) -> Bool {
        previous == section
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The section of the last update: only a change within one section animates.
    @MainActor
    final class Coordinator {
        var section: AppSection?
    }
}
