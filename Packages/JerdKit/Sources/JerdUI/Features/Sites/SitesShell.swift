/// The window services that the Sites feature uses: navigation, bringing the window forward,
/// and the window alert. `AppState` fills them in, so the models never hold the app state.
@MainActor
public struct SitesShell {
    /// Shows a destination in the window without bringing the window forward.
    public var show: (Destination) -> Void
    /// Shows a destination and brings the window forward, for menu bar commands.
    public var open: (Destination) -> Void
    /// Shows the window alert. Only a failed system setup uses it.
    public var alert: (AppAlert) -> Void

    public init(
        show: @escaping (Destination) -> Void, open: @escaping (Destination) -> Void,
        alert: @escaping (AppAlert) -> Void
    ) {
        self.show = show
        self.open = open
        self.alert = alert
    }

    /// A shell that does nothing, until `AppState` connects the real one.
    public static let detached = SitesShell(show: { _ in }, open: { _ in }, alert: { _ in })
}
