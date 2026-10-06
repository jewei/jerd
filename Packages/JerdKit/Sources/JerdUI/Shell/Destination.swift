/// A place in the main window that a link, a command, or a failure can show.
public enum Destination: Hashable, Sendable {
    /// A section with its current page and selection.
    case section(AppSection)
    /// A page of the Dashboard section.
    case dashboard(DashboardPage)
    /// An item in a feature sidebar, which also selects its section.
    case item(SidebarSelection)

    /// The section that shows this destination.
    public var section: AppSection {
        switch self {
        case .section(let section): section
        case .dashboard: .dashboard
        case .item(let selection): selection.section
        }
    }
}
