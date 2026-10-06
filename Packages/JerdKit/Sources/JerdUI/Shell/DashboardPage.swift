/// A page of the Dashboard section. The case order is the sidebar order and must not change.
public enum DashboardPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview = "Dashboard"
    case appearance = "Appearance"
    case runtimes = "Runtimes"
    case advanced = "Advanced"
    case about = "About"

    public var id: String { rawValue }

    /// The sidebar title.
    public var title: String { rawValue }

    /// The sidebar symbol. The sidebar shows the filled variant for the selected page.
    public var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .appearance: "paintbrush"
        case .runtimes: "shippingbox"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}
