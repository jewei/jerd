/// What the split of the main window shows now: the section, whether its sidebar shows, and
/// the two column views. A split view reads it and reports a sidebar that the user collapsed
/// or expanded in the split itself (a drag of the divider) with `recordSidebarVisible(_:)`.
@MainActor
public struct WorkspaceColumns {
    private let state: AppState
    /// The current section.
    public let section: AppSection
    /// True when the sidebar of the current section shows. Mail never has one.
    public let isSidebarVisible: Bool

    init(state: AppState) {
        self.state = state
        section = state.navigation.section
        isSidebarVisible = state.navigation.isSidebarVisible(in: state.navigation.section)
    }

    /// The sidebar column. It follows the section by itself.
    public var sidebar: WorkspaceSidebarColumn { WorkspaceSidebarColumn(state: state) }

    /// The detail column with the retained pages. It follows the section by itself.
    public var detail: WorkspaceDetailColumn { WorkspaceDetailColumn(state: state) }

    /// Records a sidebar change that the split view made, so the sidebar button, ⌃⌘S, and the
    /// next visit of the section agree with it. Does nothing on Mail.
    public func recordSidebarVisible(_ isVisible: Bool) {
        guard state.navigation.isSidebarVisible(in: state.navigation.section) != isVisible else { return }
        state.navigation.setSidebarVisible(isVisible)
    }
}
