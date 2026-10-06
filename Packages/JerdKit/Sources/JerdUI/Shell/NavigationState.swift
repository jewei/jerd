/// Where the main window is: the section, the dashboard page, one selection per feature
/// sidebar, and the sidebar visibility of each section. A pure value, so links, commands, and
/// the menu bar can change the section and the page together, and tests need no window.
public struct NavigationState: Equatable, Sendable {
    public private(set) var section: AppSection
    public var dashboardPage: DashboardPage
    private var selections: [AppSection: SidebarSelection] = [:]
    /// Sections whose sidebar the user hid. Mail never has a sidebar, so it is not stored.
    private var hiddenSidebars: Set<AppSection> = []

    public init(section: AppSection = .dashboard, dashboardPage: DashboardPage = .overview) {
        self.section = section
        self.dashboardPage = dashboardPage
    }

    /// Shows a destination: selects its section, and its page or sidebar item.
    public mutating func show(_ destination: Destination) {
        section = destination.section
        switch destination {
        case .section:
            break
        case .dashboard(let page):
            dashboardPage = page
        case .item(let selection):
            selections[selection.section] = selection
        }
    }

    /// The selected sidebar item of a section, if any.
    public func selection(in section: AppSection) -> SidebarSelection? {
        selections[section]
    }

    /// Applies a selection from a sidebar list. A native list refresh can report nil or an item
    /// of another section; neither may clear the selection that the user made.
    public mutating func select(_ selection: SidebarSelection?) {
        guard let selection, selection.section == section else { return }
        selections[section] = selection
    }

    /// Removes the selection of a section, for example after its item was removed.
    public mutating func clearSelection(in section: AppSection) {
        selections[section] = nil
    }

    /// True when the sidebar of `section` shows. Each section remembers its own state.
    public func isSidebarVisible(in section: AppSection) -> Bool {
        section.hasSidebar && !hiddenSidebars.contains(section)
    }

    /// True when the current section has a sidebar that the user can show or hide.
    public var canToggleSidebar: Bool { section.hasSidebar }

    /// Shows or hides the sidebar of the current section. Does nothing on Mail.
    public mutating func toggleSidebar() {
        setSidebarVisible(!isSidebarVisible(in: section))
    }

    /// Records a sidebar change of the current section, for example from the split view.
    public mutating func setSidebarVisible(_ isVisible: Bool) {
        guard section.hasSidebar else { return }
        if isVisible {
            hiddenSidebars.remove(section)
        } else {
            hiddenSidebars.insert(section)
        }
    }
}
